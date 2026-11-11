import Foundation
import os
@testable import Networking

/// One stubbed backend per test, addressed by a unique host so parallel tests never share state.
final class StubServer: Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var chunks: [Data] = []
        /// Pause between chunks (seconds).
        var chunkDelay: TimeInterval = 0
        /// When set, repeats this chunk every `chunkDelay` until the client stops loading.
        var endless: Data?

        init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.chunks = body.isEmpty ? [] : [body]
        }

        init(status: Int = 200, json: String, headers: [String: String] = [:]) {
            self.init(
                status: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 },
                body: Data(json.utf8)
            )
        }
    }

    typealias Handler = @Sendable (URLRequest) -> Reply

    private struct State {
        var handler: Handler = { _ in Reply() }
        var requests: [URLRequest] = []
        var bodies: [Data] = []
        var stopCount = 0
    }

    let host: String
    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let registry = OSAllocatedUnfairLock(initialState: [String: StubServer]())

    init(_ handler: @escaping Handler = { _ in Reply() }) {
        host = "t-\(UUID().uuidString.prefix(8).lowercased()).stub"
        state.withLock { $0.handler = handler }
        Self.registry.withLock { $0[host] = self }
    }

    deinit { _ = Self.registry.withLock { $0.removeValue(forKey: host) } }

    var baseURL: URL { URL(string: "https://\(host)") ?? URL(fileURLWithPath: "/") }
    var requests: [URLRequest] { state.withLock { $0.requests } }
    var bodies: [Data] { state.withLock { $0.bodies } }
    var stopCount: Int { state.withLock { $0.stopCount } }

    func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    func session() -> URLSession { URLSession(configuration: configuration()) }

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
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    override class func canInit(with request: URLRequest) -> Bool {
        StubServer.server(for: request.url?.host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

    override func stopLoading() {
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
func chunked(_ data: Data, size: Int) -> [Data] {
    stride(from: 0, to: data.count, by: size).map { data.subdata(in: $0..<min($0 + size, data.count)) }
}

/// Polls `condition` until it holds or `timeout` seconds pass.
func waitUntil(timeout: TimeInterval = 5, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return condition()
}
