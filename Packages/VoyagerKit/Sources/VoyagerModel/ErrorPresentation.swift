import Foundation

public enum ErrorPresentationKind: Sendable, Equatable {
    case unauthorized, rateLimited, network, server, other
}

/// What an error banner needs to know about a failure. `APIError` conforms in Networking.
public protocol ErrorPresentable: Sendable {
    var presentationKind: ErrorPresentationKind { get }
    /// The server's own text; the only text shown as-is.
    var userFacingDetail: String? { get }
}
