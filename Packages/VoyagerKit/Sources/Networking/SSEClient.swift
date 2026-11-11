import Foundation
import VoyagerModel

/// Streams `POST` SSE endpoints (`/api/search`, `/api/chat`). Parsing and JSON decoding run in a detached
/// task at `.userInitiated`, never on the main actor. A stream that ends without a terminal event finishes
/// normally; the caller detects a missing `done` and decides on the single retry.
public struct SSEClient: Sendable {
    private let server: ServerEnvironment
    private let tokens: any AccessTokenProvider
    private let session: URLSession
    private let observer: (any APIObserver)?
    /// Test hook, called on the parsing task for every dispatched message.
    private let parseHook: (@Sendable () -> Void)?

    /// Works on a copy of `configuration`: 600 s request timeout, effectively no resource timeout.
    public init(
        server: ServerEnvironment,
        tokens: any AccessTokenProvider,
        configuration: URLSessionConfiguration = .default,
        observer: (any APIObserver)? = nil
    ) {
        self.init(server: server, tokens: tokens, configuration: configuration, observer: observer, parseHook: nil)
    }

    init(
        server: ServerEnvironment,
        tokens: any AccessTokenProvider,
        configuration: URLSessionConfiguration,
        observer: (any APIObserver)?,
        parseHook: (@Sendable () -> Void)?
    ) {
        let configuration = (configuration.copy() as? URLSessionConfiguration) ?? .default
        configuration.timeoutIntervalForRequest = StreamTimeouts.request
        configuration.timeoutIntervalForResource = StreamTimeouts.resource
        self.server = server
        self.tokens = tokens
        self.session = URLSession(configuration: configuration)
        self.observer = observer
        self.parseHook = parseHook
    }

    /// `telemetryName` is a route template (`/api/search`), the only name the observer ever sees.
    public func stream(
        path: String, telemetryName: String, body: some Encodable & Sendable, auth: AuthMode
    ) -> AsyncThrowingStream<JSONValue, Error> {
        let (stream, continuation) = AsyncThrowingStream<JSONValue, Error>.makeStream()
        let task = Task.detached(priority: .userInitiated) {
            do {
                try await run(path: path, telemetryName: telemetryName, body: body, auth: auth, continuation: continuation)
                continuation.finish()
            } catch {
                let mapped = Self.mapped(error)
                if mapped == .network || mapped == .interrupted { observer?.didFail(endpoint: telemetryName, status: 0) }
                continuation.finish(throwing: mapped)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private func run(
        path: String, telemetryName: String, body: some Encodable & Sendable, auth: AuthMode,
        continuation: AsyncThrowingStream<JSONValue, Error>.Continuation
    ) async throws {
        guard let base = server.baseURL else { throw APIError.notConfigured }
        var retried = false
        while true {
            let token = auth == .none ? nil : await tokens.currentToken()
            if auth == .required, token == nil { throw APIError.unauthorized }
            let request = try RequestFactory.request(
                base: base, method: .post, path: path, body: body, token: token,
                timeout: StreamTimeouts.request, accept: "text/event-stream"
            )
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.network }
            if !(200..<300).contains(http.statusCode) {
                let data = try await Self.readErrorBody(bytes)
                if http.statusCode == 401, let token {
                    let refreshed = await tokens.unauthorized(token: token)
                    if refreshed, !retried {
                        retried = true
                        continue
                    }
                }
                observer?.didFail(endpoint: telemetryName, status: http.statusCode)
                throw ErrorMapping.map(response: http, body: data)
            }
            if http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/html") == true {
                throw APIError.decoding // a captive portal's page, not a stream
            }
            try await pump(bytes, into: continuation)
            return
        }
    }

    private func pump(
        _ bytes: URLSession.AsyncBytes, into continuation: AsyncThrowingStream<JSONValue, Error>.Continuation
    ) async throws {
        var parser = SSEParser()
        let decoder = JSONDecoder()
        func deliver(_ message: SSEMessage) -> Bool {
            parseHook?()
            // A malformed event is skipped rather than ending a search that is otherwise healthy.
            guard let value = try? decoder.decode(JSONValue.self, from: Data(message.data.utf8)) else { return true }
            if case .terminated = continuation.yield(value) { return false }
            return true
        }
        do {
            for try await byte in bytes {
                if let message = parser.feed(byte), !deliver(message) { return }
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw APIError.cancelled }
            throw APIError.interrupted
        }
        if let message = parser.finish() { _ = deliver(message) }
    }

    private static func readErrorBody(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= 65_536 { break }
        }
        return data
    }

    private static func mapped(_ error: Error) -> APIError {
        if let error = error as? APIError { return error }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return .cancelled }
        return .network
    }
}
