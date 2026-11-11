import Foundation
import Networking
import VoyagerModel

public struct LiveWatchesRepository: WatchesRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func fareWatches() async throws -> [FareWatch] { try await api.send(Endpoints.fareWatches()) }
    public func priceWatches(kind: WatchKind?) async throws -> [PriceWatch] {
        try await api.send(Endpoints.priceWatches(kind: kind))
    }
    public func createFare(_ watch: NewFareWatch) async throws -> FareWatch { try await api.send(Endpoints.createFareWatch(watch)) }
    public func createPrice(_ watch: NewPriceWatch) async throws -> PriceWatch { try await api.send(Endpoints.createPriceWatch(watch)) }

    /// Unwraps `{"watch": {...}|null}`.
    public func match(_ query: WatchMatchQuery) async throws -> JSONValue? {
        guard let watch = try await api.send(Endpoints.matchWatch(query)).watch, !watch.isNull else { return nil }
        return watch
    }

    public func patch(kind: WatchKind, id: Int, _ patch: WatchPatch) async throws -> WatchItem {
        kind == .flight
            ? .fare(try await api.send(Endpoints.patchFareWatch(id: id, patch)))
            : .price(try await api.send(Endpoints.patchPriceWatch(id: id, patch)))
    }

    public func delete(kind: WatchKind, id: Int) async throws { _ = try await api.send(Endpoints.deleteWatch(kind: kind, id: id)) }

    public func check(kind: WatchKind, id: Int) async throws -> WatchItem {
        kind == .flight
            ? .fare(try await api.send(Endpoints.checkFareWatch(id: id)))
            : .price(try await api.send(Endpoints.checkPriceWatch(id: id)))
    }

    public func liveCheck(_ request: LiveCheckRequest) async throws -> LiveCheckResult {
        try await api.send(Endpoints.liveCheck(request))
    }
}
