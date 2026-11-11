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

    private struct Entry: Decodable {
        let value: AuthProviderInfo?
        init(from decoder: any Decoder) throws { value = try? AuthProviderInfo(from: decoder) }
    }

    private struct Wrapped: Decodable { let providers: [Entry] }

    /// Lenient list decoding for the `/api/auth/providers` body (a bare array or `{"providers": [...]}`):
    /// entries with an unknown id or a bad shape are skipped instead of failing the whole list.
    /// `LiveAuthAPI` (Task 12) uses this.
    public static func decodeList(from data: Data) throws -> [AuthProviderInfo] {
        let decoder = JSONDecoder()
        if let entries = try? decoder.decode([Entry].self, from: data) {
            return entries.compactMap(\.value)
        }
        return try decoder.decode(Wrapped.self, from: data).providers.compactMap(\.value)
    }
}

/// Caches the provider list for the process. A 404 or any error leaves all four unconfigured, with no retry.
public actor AuthProviderCatalog {
    private let api: AuthAPI
    private var inFlight: Task<[AuthProviderID: AuthProviderInfo], Never>?

    public init(api: AuthAPI) { self.api = api }

    /// The actor is reentrant, so the first call stores one task that every caller awaits.
    public func providers() async -> [AuthProviderID: AuthProviderInfo] {
        if let inFlight { return await inFlight.value }
        let api = api
        let task = Task<[AuthProviderID: AuthProviderInfo], Never> {
            var result = Dictionary(
                uniqueKeysWithValues: AuthProviderID.allCases.map { ($0, AuthProviderInfo(id: $0, configured: false)) })
            if let list = try? await api.providers() {
                for info in list { result[info.id] = info }
            }
            return result
        }
        inFlight = task
        return await task.value
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
