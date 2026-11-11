import Foundation
import VoyagerModel

public enum APIError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden(String?)
    case notFound(String?)
    case rateLimited(message: String, retryAfter: Int?)
    case client(status: Int, detail: String?, code: String?, body: JSONValue)
    case server(status: Int, detail: String?)
    case network
    case interrupted
    case decoding
    case notConfigured
    case cancelled

    /// The server's `detail` text, the only text that may be shown as-is. A list or object `detail`
    /// contributes its `message` (or nil). Client-side failures never carry exception text.
    public var userFacingDetail: String? {
        switch self {
        case .forbidden(let detail), .notFound(let detail): return detail
        case .rateLimited(let message, _): return message.isEmpty ? nil : message
        case .client(_, let detail, _, _), .server(_, let detail): return detail
        case .unauthorized, .network, .interrupted, .decoding, .notConfigured, .cancelled: return nil
        }
    }
}
