import Foundation

public protocol AuthAPI: Sendable {
    func login(username: String, password: String) async throws -> LoginResponse
    /// Returns the new access token.
    func changePassword(current: String, new: String) async throws -> String
    func me() async throws -> User
    func providers() async throws -> [AuthProviderInfo]
}
