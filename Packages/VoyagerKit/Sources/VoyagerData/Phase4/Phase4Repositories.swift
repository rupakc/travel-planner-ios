import Foundation
import Networking
import VoyagerModel

// Share links 2.0 (`docs/Sharing-API.md`) management routes. The public reads (`GET /share/{token}`, the page, the card)
// are not here: the viewer uses `PlansRepository.shared`, and the card is a plain PNG download (`ShareCardLoader`).
extension Endpoints {
    public static func sharesCreate(_ request: ShareRequest) -> Endpoint<Share> {
        Endpoint(method: .post, path: "/api/shares", telemetryName: "/api/shares", body: request)
    }

    public static func sharesList() -> Endpoint<ShareList> {
        Endpoint(path: "/api/shares", telemetryName: "/api/shares")
    }

    public static func sharesRevoke(token: String) -> Endpoint<Empty> {
        Endpoint(
            method: .delete, path: "/api/shares/" + Self.pathSegment(token), telemetryName: "/api/shares/:token")
    }

    /// One URL path segment: everything outside the unreserved set is percent-encoded, so a token can never add a
    /// slash, a query or a dot segment.
    static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

public struct LiveSharesRepository: SharesRepository {
    private let api: APIClient
    private let locale: @Sendable () -> AppLanguage

    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.api = api
        self.locale = locale
    }

    /// The page language is the app's language unless the request names one.
    public func create(_ request: ShareRequest) async throws -> Share {
        var request = request
        if request.locale == nil { request.locale = locale().rawValue }
        return try await api.send(Endpoints.sharesCreate(request))
    }

    public func list() async throws -> ShareList { try await api.send(Endpoints.sharesList()) }

    public func revoke(token: String) async throws { _ = try await api.send(Endpoints.sharesRevoke(token: token)) }
}
