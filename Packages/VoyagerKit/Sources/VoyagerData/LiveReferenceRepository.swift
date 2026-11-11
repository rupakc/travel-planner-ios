import Foundation
import Networking
import VoyagerModel

public struct LiveReferenceRepository: ReferenceRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func airports(_ query: String, limit: Int) async throws -> [AirportSuggestion] {
        try await api.send(Endpoints.airports(query, limit: limit))
    }
    public func nationalities(_ query: String, limit: Int) async throws -> [NationalitySuggestion] {
        try await api.send(Endpoints.nationalities(query, limit: limit))
    }
}
