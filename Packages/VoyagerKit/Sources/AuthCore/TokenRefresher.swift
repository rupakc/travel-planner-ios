import Foundation

public protocol TokenRefresher: Sendable {
    func refresh(_ s: Session) async throws -> Session
}

public struct NoTokenRefresher: TokenRefresher {
    public init() {}
    public func refresh(_ s: Session) async throws -> Session { throw AuthError.refreshUnavailable }
}
