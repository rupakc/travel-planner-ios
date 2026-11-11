import Foundation
import Networking
import VoyagerModel

public struct LiveHealthRepository: HealthRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func health() async throws -> Health { try await api.send(Endpoints.health()) }

    /// A 404 (older backend) is `nil`, never an error.
    public func clientConfig() async throws -> ClientConfig? {
        do {
            return try await api.send(Endpoints.config())
        } catch APIError.notFound {
            return nil
        }
    }
}
