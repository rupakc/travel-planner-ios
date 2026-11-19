import Foundation
import Networking
import Testing
import VoyagerModel

@testable import VoyagerData

struct CarbonDataTests {
    @Test func test_route() {
        let trip = Endpoints.carbonTrip(body: ["diet": "mixed"])
        #expect(trip.method == .post && trip.path == "/api/carbon/trip" && trip.auth == .optional)
        #expect(trip.telemetryName == "/api/carbon/trip")
    }

    @Test func test_postsTheBodyAsIsWithoutALocale() async throws {
        let h = try Harness(language: .de) { _ in .init(json: #"{"total_kg": 245.1, "per_person_kg": 122.5}"#) }
        let body: JSONValue = ["search": ["origin": "London"], "results": ["flights": [:]], "diet": "vegan"]
        let answer = try await LiveCarbonRepository(api: h.api).trip(body)
        #expect(answer["total_kg"].double == 245.1)
        #expect(h.request?.url?.path == "/api/carbon/trip")
        #expect(h.request?.httpMethod == "POST")
        #expect(try h.body() == body)
    }

    @Test func test_404IsNotFound() async throws {
        let h = try Harness { _ in .init(status: 404, json: #"{"detail": "Not Found"}"#) }
        do {
            _ = try await LiveCarbonRepository(api: h.api).trip(["diet": "mixed"])
            Issue.record("expected a 404")
        } catch let error as APIError {
            guard case .notFound = error else {
                Issue.record("expected .notFound, got \(error)")
                return
            }
        }
    }
}
