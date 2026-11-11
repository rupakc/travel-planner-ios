import Foundation
import Networking
import VoyagerModel

public struct LiveRecentSearchesRepository: RecentSearchesRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func list() async throws -> [RecentSearch] { try await api.send(Endpoints.recentSearches()) }
    public func record(_ search: JSONValue) async throws { _ = try await api.send(Endpoints.recordRecentSearch(search)) }
    public func delete(id: Int) async throws { _ = try await api.send(Endpoints.deleteRecentSearch(id: id)) }
}
