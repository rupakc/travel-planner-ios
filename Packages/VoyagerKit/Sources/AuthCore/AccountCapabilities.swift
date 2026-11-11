import Foundation
import VoyagerModel

/// What the backend offers beyond Phase 0. Every flag is false until the backend says otherwise.
public struct AccountCapabilities: Sendable, Equatable {
    public var signUp: Bool
    public var passwordReset: Bool
    public var deleteAccount: Bool
    public var refreshTokens: Bool

    public init(signUp: Bool = false, passwordReset: Bool = false, deleteAccount: Bool = false, refreshTokens: Bool = false) {
        self.signUp = signUp
        self.passwordReset = passwordReset
        self.deleteAccount = deleteAccount
        self.refreshTokens = refreshTokens
    }

    public static let none = AccountCapabilities()

    /// Reads `features.signup`, `password_reset`, `account_deletion`, `refresh_tokens`; missing reads as false.
    public static func from(features: [String: JSONValue]?) -> AccountCapabilities {
        guard let features else { return .none }
        func flag(_ k: String) -> Bool { features[k]?.bool ?? false }
        return AccountCapabilities(
            signUp: flag("signup"), passwordReset: flag("password_reset"),
            deleteAccount: flag("account_deletion"), refreshTokens: flag("refresh_tokens"))
    }
}
