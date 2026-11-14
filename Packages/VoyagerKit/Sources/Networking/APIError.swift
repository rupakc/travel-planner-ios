import Foundation
import VoyagerModel

public enum APIError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden(String?)
    case notFound(String?)
    case rateLimited(message: String, retryAfter: Int?)
    case client(status: Int, detail: String?, code: String?, body: JSONValue)
    /// `code` is the 5xx body's `error_code` / `detail.code` when it had one (the body itself is never kept).
    case server(status: Int, detail: String?, code: String? = nil)
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
        case .client(_, let detail, _, _), .server(_, let detail, _): return detail
        case .unauthorized, .network, .interrupted, .decoding, .notConfigured, .cancelled: return nil
        }
    }
}

/// The 5xx codes of the shared error envelope that clients give their own copy. Anything else stays a generic server error.
public enum ServiceCode: String, Sendable, Hashable, CaseIterable {
    case aiLimit = "ai_limit"
    case aiBilling = "ai_billing"
    case livePricesOff = "live_prices_off"
    case groundingUnavailable = "grounding_unavailable"
    case liveCheckFailed = "live_check_failed"
}

extension APIError {
    /// The raw `error_code` of a 5xx answer, nil for everything else.
    public var serverCode: String? {
        if case .server(_, _, let code) = self { return code }
        return nil
    }

    /// The known service code of a 5xx answer (`503 ai_limit`, `502 live_check_failed`, ...); nil when absent or unknown.
    public var serviceCode: ServiceCode? { serverCode.flatMap(ServiceCode.init(rawValue:)) }
}
