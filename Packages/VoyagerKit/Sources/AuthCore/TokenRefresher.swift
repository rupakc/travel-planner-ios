import Foundation

public protocol TokenRefresher: Sendable {
    func refresh(_ session: Session) async throws -> Session
}

public struct NoTokenRefresher: TokenRefresher {
    public init() {}
    public func refresh(_ session: Session) async throws -> Session { throw AuthError.refreshUnavailable }
}
