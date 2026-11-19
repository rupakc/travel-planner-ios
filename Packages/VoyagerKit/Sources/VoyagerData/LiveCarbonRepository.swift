import Foundation
import Networking
import VoyagerModel

extension Endpoints {
    /// `POST /api/carbon/trip`: anonymous calls are fine; no language (lines carry stable `kind`/`code` + `params`).
    public static func carbonTrip(body: JSONValue) -> Endpoint<JSONValue> {
        Endpoint(method: .post, path: "/api/carbon/trip", telemetryName: "/api/carbon/trip", body: body, auth: .optional)
    }
}

public struct LiveCarbonRepository: CarbonRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func trip(_ body: JSONValue) async throws -> JSONValue {
        try await api.send(Endpoints.carbonTrip(body: body))
    }
}
