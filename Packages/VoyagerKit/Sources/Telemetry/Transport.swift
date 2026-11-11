import Foundation

public enum TransportOutcome: Sendable, Equatable {
    case ok
    /// 404: telemetry is disabled on the server. The client turns itself off for the session.
    case disabled
    case retryAfter(Int)
    /// Any other 4xx except 408 and 429: the batch would fail forever.
    case drop
    case failed
}

public protocol TelemetryTransport: Sendable {
    func post(_ url: URL, body: Data, gzipped: Bool, token: String?) async -> TransportOutcome
}

public struct URLSessionTelemetryTransport: TelemetryTransport {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    public func post(_ url: URL, body: Data, gzipped: Bool, token: String?) async -> TransportOutcome {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if gzipped { request.setValue("gzip", forHTTPHeaderField: "Content-Encoding") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            return Self.outcome(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        } catch {
            return .failed
        }
    }

    static func outcome(status: Int, retryAfter: String?) -> TransportOutcome {
        switch status {
        case 200..<300: return .ok
        case 404: return .disabled
        case 429: return .retryAfter(retryAfter.flatMap { Int($0) }.map { max(1, $0) } ?? 60)
        case 408: return .failed
        case 400..<500: return .drop
        default: return .failed
        }
    }
}
