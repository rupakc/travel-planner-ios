import Foundation

/// Request timeout classes (Android parity: `@DefaultHttp` 30 s, `@AiHttp` 300 s; agents can run 240 s).
public enum TimeoutClass: Sendable, Equatable {
    case standard
    case ai

    public var seconds: TimeInterval {
        switch self {
        case .standard: return 30
        case .ai: return 300
        }
    }
}

/// Streaming (`/api/search`, `/api/chat`) timeouts: 600 s of silence, no overall resource limit.
enum StreamTimeouts {
    static let request: TimeInterval = 600
    /// "No resource timeout": one year, since `URLSession` treats very large values unevenly.
    static let resource: TimeInterval = 365 * 24 * 3600
}
