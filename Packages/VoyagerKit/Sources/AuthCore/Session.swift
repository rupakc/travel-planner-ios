import Foundation

public enum SignInMethod: String, Codable, Sendable {
    case password, apple, google, facebook, github
}

public struct Session: Codable, Sendable, Equatable {
    public var accessToken: String
    /// Stays nil until Phase 1 (refresh tokens).
    public var refreshToken: String?
    /// Read from the JWT `exp` claim without verifying the signature.
    public var accessExpiresAt: Date?
    public var user: User
    public var method: SignInMethod

    public init(
        accessToken: String, refreshToken: String? = nil, accessExpiresAt: Date? = nil,
        user: User, method: SignInMethod
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
        self.user = user
        self.method = method
    }

    /// Builds a session from a fresh access token, reading `exp` from the JWT.
    public init(accessToken: String, user: User, method: SignInMethod) {
        self.init(
            accessToken: accessToken, refreshToken: nil,
            accessExpiresAt: JWTClaims.expiry(of: accessToken), user: user, method: method)
    }
}

enum JWTClaims {
    static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = obj["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

public enum AuthError: Error, Equatable {
    case invalidCredentials, comingSoon(AuthProviderID), refreshUnavailable, sessionExpired
}
