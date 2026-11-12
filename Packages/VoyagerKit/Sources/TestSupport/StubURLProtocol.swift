import Foundation
import os

/// One stubbed backend per test, addressed by a unique host so parallel tests never share state.
/// Point a client at `baseURL` with `configuration()` / `session()`; every request is recorded.
public final class StubServer: Sendable {
    public struct Reply: Sendable {
        public var status = 200
        public var headers: [String: String] = [:]
        public var chunks: [Data] = []
        /// Pause between chunks (seconds).
        public var chunkDelay: TimeInterval = 0
        /// When set, repeats this chunk every `chunkDelay` until the client stops loading.
        public var endless: Data?

        public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.chunks = body.isEmpty ? [] : [body]
        }

        public init(status: Int = 200, json: String, headers: [String: String] = [:]) {
            self.init(
                status: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 },
                body: Data(json.utf8)
            )
        }
    }

    public typealias Handler = @Sendable (URLRequest) -> Reply

    private struct State {
        var handler: Handler = { _ in Reply() }
        var requests: [URLRequest] = []
        var bodies: [Data] = []
        var stopCount = 0
    }

    public let host: String
    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let registry = OSAllocatedUnfairLock(initialState: [String: StubServer]())

    public init(_ handler: @escaping Handler = { _ in Reply() }) {
        host = "t-\(UUID().uuidString.prefix(8).lowercased()).stub"
        state.withLock { $0.handler = handler }
        Self.registry.withLock { $0[host] = self }
    }

    deinit { _ = Self.registry.withLock { $0.removeValue(forKey: host) } }

    public var baseURL: URL { URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/") }
    public var requests: [URLRequest] { state.withLock { $0.requests } }
    public var bodies: [Data] { state.withLock { $0.bodies } }
    public var stopCount: Int { state.withLock { $0.stopCount } }

    public func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    public func session() -> URLSession { URLSession(configuration: configuration()) }

    fileprivate static func server(for host: String?) -> StubServer? {
        guard let host else { return nil }
        return registry.withLock { $0[host] }
    }

    fileprivate func record(_ request: URLRequest, body: Data) -> Reply {
        let handler = state.withLock { state -> Handler in
            state.requests.append(request)
            state.bodies.append(body)
            return state.handler
        }
        return handler(request)
    }

    fileprivate func didStop() { state.withLock { $0.stopCount += 1 } }
}

// Test double: all mutable state (`stopped`) is behind a lock, and the instance is only touched by
// URLSession and its own delivery queue, so crossing isolation domains is safe.
public final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    override public static func canInit(with request: URLRequest) -> Bool {
        StubServer.server(for: request.url?.host) != nil
    }

    override public static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override public func startLoading() {
        guard let url = request.url, let server = StubServer.server(for: url.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let reply = server.record(request, body: Self.readBody(request))
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
        DispatchQueue.global().async { [self] in
            guard let response else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in reply.chunks {
                if stopped.withLock({ $0 }) { return }
                client?.urlProtocol(self, didLoad: chunk)
                if reply.chunkDelay > 0 { Thread.sleep(forTimeInterval: reply.chunkDelay) }
            }
            while let endless = reply.endless, !stopped.withLock({ $0 }) {
                client?.urlProtocol(self, didLoad: endless)
                Thread.sleep(forTimeInterval: max(reply.chunkDelay, 0.005))
            }
            if !stopped.withLock({ $0 }) { client?.urlProtocolDidFinishLoading(self) }
        }
    }

    override public func stopLoading() {
        stopped.withLock { $0 = true }
        StubServer.server(for: request.url?.host)?.didStop()
    }

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Splits `data` into chunks of `size` bytes.
public func chunked(_ data: Data, size: Int) -> [Data] {
    stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
}

/// Polls `condition` until it holds or `timeout` seconds pass.
public func waitUntil(timeout: TimeInterval = 5, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}

/// `waitUntil` for main-actor state (models, stores).
@MainActor
public func waitUntilOnMain(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}
