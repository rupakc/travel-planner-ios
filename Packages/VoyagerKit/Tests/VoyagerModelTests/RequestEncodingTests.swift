import Foundation
import Testing
@testable import VoyagerModel

@Suite struct RequestEncodingTests {
    private func object(_ value: some Encodable) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data).object ?? [:]
    }

    @Test func test_searchRequestSnakeCaseAndOmitsNil() throws {
        let request = TravelSearchRequest(
            origin: "London", destination: "Tokyo", departureDate: "2026-06-01",
            budgetUsd: 4000, numTravelers: 2, locale: .de
        )
        let json = try object(request)
        #expect(Set(json.keys) == ["origin", "destination", "departure_date", "budget_usd", "num_travelers", "locale"])
        #expect(json["departure_date"] == "2026-06-01")
        #expect(json["budget_usd"] == 4000)
        #expect(json["locale"] == "de")
    }

    @Test func test_searchRequestFullRoundTrip() throws {
        let request = TravelSearchRequest(
            origin: "NYC", destination: "Tokyo", departureDate: "2026-04-01", returnDate: "2026-04-08",
            interests: ["food"], destinations: ["Tokyo", "Kyoto"], destinationNights: [3, 4],
            mustInclude: [["name": "Senso-ji"]], importSource: ["title": "Blog"]
        )
        let back = try JSONDecoder().decode(TravelSearchRequest.self, from: JSONEncoder().encode(request))
        #expect(back == request)
        #expect(try object(request)["import_source"]?["title"] == "Blog")
    }

    @Test func test_chatRequestShape() throws {
        let request = ChatRequest(messages: [ChatMessage(role: "user", content: "Plan Bangkok")], locale: .de)
        let json = try object(request)
        #expect(Set(json.keys) == ["messages", "selections", "search_results", "session_context", "locale"])
        #expect(json["messages"]?[0]["role"] == "user")
        #expect(json["selections"] == [:])
        #expect(json["locale"] == "de")
    }

    @Test func test_newPriceWatchRidesUnderKindKey() throws {
        let watch = NewPriceWatch(kind: .hotel, spec: ["name": "Lumen"], planId: 3, alertMode: "any_drop")
        let json = try object(watch)
        #expect(Set(json.keys) == ["kind", "hotel", "plan_id", "alert_mode"])
        #expect(json["hotel"]?["name"] == "Lumen")
        #expect(try JSONDecoder().decode(NewPriceWatch.self, from: JSONEncoder().encode(watch)) == watch)
    }

    @Test func test_matchQueryFlightIsFlat() throws {
        let flight = try object(WatchMatchQuery(kind: .flight, spec: ["origin": "BER"], planId: 1))
        #expect(Set(flight.keys) == ["origin", "plan_id"])
        let trip = try object(WatchMatchQuery(kind: .trip, spec: ["plan_id": 1]))
        #expect(Set(trip.keys) == ["kind", "trip"])
    }

    @Test func test_deviceRegistrationAndLiveCheck() throws {
        let device = try object(DeviceRegistration(token: "t", platform: "ios", locale: "de"))
        #expect(Set(device.keys) == ["token", "platform", "locale"])
        let live = try object(LiveCheckRequest(kind: .hotel, watchId: 5))
        #expect(live["watch_id"] == 5)
        #expect(live["kind"] == "hotel")
    }
}
