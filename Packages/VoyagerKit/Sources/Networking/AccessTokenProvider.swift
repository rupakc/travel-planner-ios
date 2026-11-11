import Foundation

public protocol AccessTokenProvider: Sendable {
    /// The bearer token for the signed-in user, or nil when signed out.
    func currentToken() async -> String?
    /// A request that carried `token` got a 401. Returns true when a fresh token now exists (the client
    /// retries once). Returns false when `token` is stale (already replaced) or the session was ended.
    func unauthorized(token: String) async -> Bool
}
