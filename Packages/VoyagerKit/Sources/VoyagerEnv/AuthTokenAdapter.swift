import AuthCore
import Foundation
import Networking

/// `AccessTokenProvider` over `AuthState` (Task 7): the token is read without a main-actor hop; a 401 is
/// handed to `AuthState.handleUnauthorized(token:)`, which ignores a stale token, tries a refresher and
/// otherwise signs out with `.sessionExpired`.
public struct AuthTokenAdapter: AccessTokenProvider {
    private let auth: AuthState

    public init(auth: AuthState) { self.auth = auth }

    public func currentToken() async -> String? { auth.tokenSnapshot() }

    /// True only when `token` was the current token and a different one exists afterwards (the client
    /// retries once). A stale token (already replaced) changes nothing and answers false.
    public func unauthorized(token: String) async -> Bool {
        guard await currentAccessToken() == token else { return false }
        await auth.handleUnauthorized(token: token)
        guard let fresh = await currentAccessToken() else { return false }
        return fresh != token
    }

    @MainActor private func currentAccessToken() -> String? { auth.session?.accessToken }
}
