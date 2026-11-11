import Foundation
import Networking
import VoyagerModel

public struct LiveCompareRepository: CompareRepository {
    private let api: APIClient
    private let locale: @Sendable () -> AppLanguage
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.api = api
        self.locale = locale
    }

    public func summary(_ request: TravelSearchRequest) async throws -> CompareSummary {
        try await api.send(Endpoints.compare(body: try RequestBody.withLocale(request, locale())))
    }
}
