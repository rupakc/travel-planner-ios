import Foundation

public struct User: Codable, Sendable, Equatable {
    public var username: String
    public var isAdmin: Bool
    public var requiresPasswordChange: Bool
    public var email: String?

    public init(username: String, isAdmin: Bool = false, requiresPasswordChange: Bool = false, email: String? = nil) {
        self.username = username
        self.isAdmin = isAdmin
        self.requiresPasswordChange = requiresPasswordChange
        self.email = email
    }

    enum CodingKeys: String, CodingKey {
        case username, email
        case isAdmin = "is_admin"
        case requiresPasswordChange = "requires_password_change"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decode(String.self, forKey: .username)
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        requiresPasswordChange = try container.decodeIfPresent(Bool.self, forKey: .requiresPasswordChange) ?? false
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }
}

public struct LoginResponse: Codable, Sendable, Equatable {
    public var accessToken: String
    public var tokenType: String
    public var user: User

    public init(accessToken: String, tokenType: String = "bearer", user: User) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case user
    }
}
