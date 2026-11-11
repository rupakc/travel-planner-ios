import Foundation
import Networking
import VoyagerModel

public struct LiveAgentsRepository: AgentsRepository {
    private let api: APIClient
    private let locale: @Sendable () -> AppLanguage
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.api = api
        self.locale = locale
    }

    public func filtered(_ section: FilterableSection, request: TravelSearchRequest, filters: JSONValue) async throws -> JSONValue {
        let body = try RequestBody.merged(request, extra: filters, locale())
        return try await api.send(Endpoints.filtered(section, body: body))
    }

    public func fareCalendar(_ request: TravelSearchRequest) async throws -> JSONValue {
        try await api.send(Endpoints.fareCalendar(request))
    }

    public func stressTest(itinerary: JSONValue, request: TravelSearchRequest) async throws -> JSONValue {
        let body = try RequestBody.merged(request, extra: .object(["itinerary": itinerary]), locale())
        return try await api.send(Endpoints.stressTest(body: body))
    }

    public func layover(_ body: JSONValue) async throws -> JSONValue {
        try await api.send(Endpoints.layover(body: try RequestBody.withLocale(body, locale())))
    }
}
