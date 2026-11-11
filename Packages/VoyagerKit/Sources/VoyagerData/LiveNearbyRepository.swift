import Foundation
import Networking
import VoyagerModel

public struct LiveNearbyRepository: NearbyRepository {
    private let api: APIClient
    private let locale: @Sendable () -> AppLanguage
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.api = api
        self.locale = locale
    }

    /// Near me takes `language` rather than `locale`; it is filled from the app language when the caller left it nil.
    public func nearby(_ request: NearbyRequest) async throws -> NearbyResponse {
        var request = request
        if request.language == nil { request.language = locale().rawValue }
        return try await api.send(Endpoints.nearby(request))
    }
}
