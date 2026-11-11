import AuthCore
import Foundation

/// A scripted `AuthAPI`. Login answers a token for the given user, change-password a new token, and the
/// provider list is empty (all four social buttons "coming soon"), unless scripted otherwise.
public final class FakeAuthAPI: AuthAPI {
    public let onLogin = FakeCall<(username: String, password: String), LoginResponse>("auth.login") { input in
        LoginResponse(accessToken: "fake-token-\(input.username)", user: User(username: input.username))
    }
    public let onChangePassword = FakeCall<(current: String, new: String), String>("auth.changePassword") { _ in
        "fake-token-changed"
    }
    public let onMe = FakeCall<Void, User>("auth.me")
    public let onProviders = FakeCall<Void, [AuthProviderInfo]>("auth.providers") { _ in [] }

    public init() {}

    public func login(username: String, password: String) async throws -> LoginResponse {
        try await onLogin((username, password))
    }

    public func changePassword(current: String, new: String) async throws -> String {
        try await onChangePassword((current, new))
    }

    public func me() async throws -> User { try await onMe() }
    public func providers() async throws -> [AuthProviderInfo] { try await onProviders() }
}

extension User {
    /// A signed-in, non-admin user with nothing pending.
    public static let sample = User(username: "amy", email: "amy@example.com")
    public static let sampleAdmin = User(username: "root", isAdmin: true)
}

extension Session {
    /// A password session for `user` with a fixed token.
    public static func sample(user: User = .sample, token: String = "fake-token") -> Session {
        Session(accessToken: token, refreshToken: nil, accessExpiresAt: nil, user: user, method: .password)
    }
}
