import Domain
import Foundation
import Testing
import VoyagerModel

@testable import SectionsUI

struct CommerceTests {
    private static let now = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01
    private static let search: JSONValue = [
        "origin": "NYC", "destination": "Tokyo", "departure_date": "2026-04-01", "return_date": "2026-04-08", "num_travelers": 2,
    ]

    private static func flight(price: Double, source: String, leg: Int? = nil, live: Bool? = nil) -> JSONValue {
        var object: [String: JSONValue] = ["price_usd": .number(price), "source": .string(source), "outbound": ["airline": "JAL"]]
        if let leg { object["leg_index"] = .number(Double(leg)) }
        if let live { object["live_fare"] = .bool(live) }
        return .object(object)
    }

    @Test func test_estimateLabelledAndNoWatch() {
        let estimate = Self.flight(price: 900, source: "estimate")
        let live = Self.flight(price: 1200, source: "google_flights", live: true)
        #expect(SectionItem(estimate).isEstimate)
        #expect(FlightRow.watchSpec(for: estimate, search: Self.search, now: Self.now) == nil)
        #expect(!SectionItem(live).isEstimate)
        let spec = FlightRow.watchSpec(for: live, search: Self.search, now: Self.now)
        #expect(spec?["origin"].string == "NYC")
        #expect(spec?["num_travelers"].int == 2)
        // A non-live fare (live_fare false) is an estimate too.
        #expect(FlightRow.watchSpec(for: Self.flight(price: 800, source: "x", live: false), search: Self.search, now: Self.now) == nil)
        // A departure that has passed, or a multi-city trip, cannot be watched.
        #expect(FlightRow.watchSpec(for: live, search: Self.search, now: Date(timeIntervalSince1970: 1_800_000_000)) == nil)
        var multi = Self.search
        if case .object(var object) = multi {
            object["destinations"] = ["Tokyo", "Seoul"]
            multi = .object(object)
        }
        #expect(FlightRow.watchSpec(for: live, search: multi, now: Self.now) == nil)
    }

    @Test func test_hotelAndActivityWatchSpecs() {
        let hotel: JSONValue = ["name": "Park Hyatt", "price_per_night_usd": 650, "total_price_usd": 4550]
        let spec = HotelRow.watchSpec(for: hotel, search: Self.search, now: Self.now)
        #expect(spec?["check_in"].string == "2026-04-01")
        #expect(spec?["rooms"].int == 1)
        #expect(spec?["adults"].int == 2)
        #expect(spec?["estimate_total"].double == 4550)
        #expect(HotelRow.watchSpec(for: hotel, search: ["destination": "Tokyo"], now: Self.now) == nil)
        let activity = ActivityRow.watchSpec(for: ["name": "Food tour", "price_usd": 120], search: Self.search)
        #expect(activity?["city"].string == "Tokyo")
        #expect(activity?["travellers"].int == 2)
        #expect(activity?["estimate_price"].double == 120)
    }

    @Test func test_multiCityLegsGrouped() {
        let data: JSONValue = [
            "trip_type": "multi_city",
            "legs": [
                ["leg_index": 0, "label": "NYC → Paris", "results": [Self.flight(price: 500, source: "google_flights")]],
                ["leg_index": 1, "label": "Paris → Rome", "results": [], "error": "none found"],
            ],
            "results": [],
        ]
        let groups = Commerce.flightGroups(data)
        #expect(groups.map(\.id) == [0, 1])
        #expect(groups[0].label == "NYC → Paris")
        #expect(groups[0].flights.first?["leg_index"].int == 0)  // injected so the plan keeps one fare per leg
        #expect(groups[1].flights.isEmpty && groups[1].error == "none found")
        let progress = Commerce.legProgress(data) { $0["price_usd"].double == 500 }
        #expect(progress.chosen == 1 && progress.total == 2)
        // A single trip is one group.
        #expect(Commerce.flightGroups(["results": [Self.flight(price: 1, source: "x")]]).count == 1)
    }

    @Test func test_selectToggles() {
        let legA = Self.flight(price: 500, source: "google_flights", leg: 0)
        let legA2 = Self.flight(price: 520, source: "google_flights", leg: 0)
        let legB = Self.flight(price: 300, source: "google_flights", leg: 1)
        var selections = Selections.empty
        selections = Selections.toggle(selections, field: "flights", item: legA)
        selections = Selections.toggle(selections, field: "flights", item: legB)
        #expect(Selections.contains(selections, field: "flights", item: legA))
        #expect(Selections.contains(selections, field: "flights", item: legB))
        // Another fare on the same leg replaces the first; the same fare again deselects.
        selections = Selections.toggle(selections, field: "flights", item: legA2)
        #expect(!Selections.contains(selections, field: "flights", item: legA))
        #expect(Selections.contains(selections, field: "flights", item: legA2))
        selections = Selections.toggle(selections, field: "flights", item: legA2)
        #expect(!Selections.contains(selections, field: "flights", item: legA2))
        #expect(Selections.contains(selections, field: "flights", item: legB))
        // Hotels, SIM and activities select through their own plan fields.
        let hotel: JSONValue = ["name": "Park Hyatt"]
        selections = Selections.toggle(selections, field: "hotel", item: hotel)
        #expect(Selections.contains(selections, field: "hotel", item: hotel))
    }

    @Test func test_hotelsGroupedByTier() {
        let hotels: [JSONValue] = [
            ["name": "A", "star_rating": 3], ["name": "B", "star_rating": 5], ["name": "C", "star_rating": 4.4],
            ["name": "D", "star_rating": 2], ["name": "E"], ["name": "F", "star_rating": 5],
        ]
        let tiers = Commerce.hotelTiers(hotels)
        #expect(tiers.map(\.tier) == [.luxury, .premium, .midRange, .budget, .other])
        #expect(tiers[0].hotels.compactMap { $0["name"].string } == ["B", "F"])
    }

    @Test func test_fromLinkActivitiesFirst() {
        let items: [JSONValue] = [["name": "A"], ["name": "B", "from_link": true], ["name": "C"], ["name": "D", "from_link": true]]
        #expect(Commerce.activitiesFromLinkFirst(items).compactMap { $0["name"].string } == ["B", "D", "A", "C"])
    }

    @Test func test_priceInsightsAndFilters() {
        let insights: JSONValue = ["price_level": "low", "typical_price_range": [900, 1400]]
        #expect(Commerce.insightLevel(insights) == "low")
        #expect(Commerce.typicalRange(insights)?.high == 1400)
        #expect(Commerce.insightLevel(["price_level": "weird"]) == nil)
        var draft = FilterDraft()
        draft.maxStops = 1
        draft.maxPrice = "1,200.5"
        let flights = draft.serverFilters(for: .flights)
        #expect(flights["max_stops"].int == 1)
        #expect(flights["max_price_usd"].double == 1200.5)
        draft.minStars = 4
        #expect(draft.serverFilters(for: .hotels).object?["max_price_per_night_usd"] != nil)
        #expect(draft.activeCount(for: .hotels) == 2)
        draft.interests = ["food", "art"]
        #expect(draft.serverFilters(for: .activities)["filter_interests"].array?.count == 2)
    }

    @Test func test_simData() {
        #expect(Commerce.simData(["data_gb": "10"]).gb == "10")
        #expect(Commerce.simData(["data_gb": 5]).gb == "5")
        #expect(Commerce.simData(["data_gb": "Unlimited"]).unlimited)
        #expect(Commerce.simData(["data_gb": "20GB"]).gb == "20")
    }

    @Test func test_fareDayParts() {
        let parts = FareCalendarStrip.dayParts("2026-04-07")
        #expect(!parts.weekday.isEmpty && !parts.date.isEmpty)
        #expect(FareCalendarStrip.deltaText(40).hasPrefix("+"))
        #expect(FareCalendarStrip.deltaText(-40).hasPrefix("−"))
        #expect(FareCalendarStrip.deltaText(nil).isEmpty)
    }
}
