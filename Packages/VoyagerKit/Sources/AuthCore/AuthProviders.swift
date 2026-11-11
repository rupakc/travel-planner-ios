import Foundation

/// Web display order. Names are brand names and are never translated.
public enum AuthProviderID: String, CaseIterable, Sendable, Codable {
    case apple, google, facebook, github

    public var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .facebook: "Facebook"
        case .github: "GitHub"
        }
    }
}

public struct AuthProviderInfo: Codable, Sendable, Equatable {
    public var id: AuthProviderID
    public var configured: Bool
    public var startURL: URL?

    public init(id: AuthProviderID, configured: Bool, startURL: URL? = nil) {
        self.id = id
        self.configured = configured
        self.startURL = startURL
    }

    enum CodingKeys: String, CodingKey {
        case id, configured
        case startURL = "start_url"
    }
}

/// Caches the provider list for the process. A 404 or any error leaves all four unconfigured, with no retry.
public actor AuthProviderCatalog {
    private let api: AuthAPI
    private var cached: [AuthProviderID: AuthProviderInfo]?

    public init(api: AuthAPI) { self.api = api }

    public func providers() async -> [AuthProviderID: AuthProviderInfo] {
        if let cached { return cached }
        var result = Dictionary(
            uniqueKeysWithValues: AuthProviderID.allCases.map { ($0, AuthProviderInfo(id: $0, configured: false)) })
        if let list = try? await api.providers() {
            for info in list { result[info.id] = info }
        }
        cached = result
        return result
    }
}

public protocol SocialSignIn: Sendable {
    func signIn(_ provider: AuthProviderID, info: AuthProviderInfo) async throws -> Session
}

public struct ComingSoonSocialSignIn: SocialSignIn {
    public init() {}
    public func signIn(_ provider: AuthProviderID, info: AuthProviderInfo) async throws -> Session {
        throw AuthError.comingSoon(provider)
    }
}
