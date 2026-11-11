import Foundation
import Networking
import VoyagerModel

public struct LiveDiscoverRepository: DiscoverRepository {
    private let api: APIClient
    private let locale: @Sendable () -> AppLanguage
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.api = api
        self.locale = locale
    }

    public func suggestions(_ request: DiscoverRequest) async throws -> [DiscoverSuggestion] {
        let body = try RequestBody.withLocale(request, locale())
        return try await api.send(Endpoints.discover(body: body)).destinations
    }
}
