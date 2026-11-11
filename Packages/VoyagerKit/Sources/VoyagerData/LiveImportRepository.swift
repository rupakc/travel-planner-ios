import Foundation
import Networking
import VoyagerModel

public struct LiveImportRepository: ImportRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func extract(_ request: LinkImportRequest) async throws -> LinkImportResult {
        try await api.send(Endpoints.importExtract(request))
    }
    public func resolvePlace(_ request: ResolvePlaceRequest) async throws -> JSONValue {
        try await api.send(Endpoints.resolvePlace(request))
    }
}
