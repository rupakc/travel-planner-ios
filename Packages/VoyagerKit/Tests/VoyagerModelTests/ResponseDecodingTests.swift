import Foundation
import Testing
import TestFixtures
@testable import VoyagerModel

@Suite struct ResponseDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(type, from: Fixtures.data("json/\(name).json"))
    }

    @Test func test_adminUserShape() throws {
        let user = try decode(AdminUser.self, "admin_user")
        #expect(user.username == "newuser")
        #expect(user.isFirstLogin == true)
        #expect(user.isAdmin == false)
        #expect(user.email == nil)
    }

    @Test func test_plans() throws {
        let plan = try decode(SavedPlan.self, "plan")
        #expect(plan.id == 7)
        #expect(plan.searchData["destination"] == "Tokyo")
        #expect(plan.shareToken == nil)
        let list = try decode([PlanSummary].self, "plans_list")
        #expect(list.map(\.id) == [7, 3])
        #expect(list[0].shareToken == "abcDEF123")
        let shared = try decode(SharedPlan.self, "shared_plan")
        #expect(shared.searchData["import_source"]["title"] == "48 hours in Tokyo")
    }

    @Test func test_preferencesAndTaste() throws {
        let prefs = try decode(Preferences.self, "preferences")
        #expect(prefs.numTravelers == 2) // "2" accepted
        #expect(prefs.existingVisas == ["US B2"])
        let taste = try decode(TasteProfile.self, "taste_profile")
        #expect(taste.signals?["interest"]?.first?.value == "food")
        #expect(taste.totalSignals == 9)
        let recent = try decode([RecentSearch].self, "recent_searches")
        #expect(recent[0].id == 12)
        #expect(recent[0].search["interests"][0] == "food")
    }

    @Test func test_typeaheads() throws {
        let airports = try decode([AirportSuggestion].self, "airports")
        #expect(airports[0].iataCode == "NRT")
        #expect(airports[1].countryCode == "JP")
        #expect(try decode([NationalitySuggestion].self, "nationalities")[0].nationality == "British")
    }

    @Test func test_fareWatch() throws {
        let watch = try decode(FareWatch.self, "fare_watch")
        #expect(watch.id == 1)
        #expect(watch.destinationCode == "LIS,CAT")
        #expect(watch.lastPrice == 150)
        #expect(watch.targetPrice == nil)
        #expect(watch.history?.count == 1)
        #expect(watch.alreadyWatching == false)
    }

    @Test func test_priceWatchKinds() throws {
        let watch = try decode(PriceWatch.self, "price_watch")
        #expect(watch.kind == .hotel)
        #expect(watch.lastObservation?.unitPrice == 88)
        #expect(watch.alreadyWatching == true)
        let unknown = try JSONDecoder().decode(PriceWatch.self, from: Data(#"{"id": 1, "kind": "cruise"}"#.utf8))
        #expect(unknown.kind == nil)
        #expect(WatchKind.allCases.map(\.rawValue) == ["flight", "hotel", "activity", "trip"])
    }

    @Test func test_notificationsPage() throws {
        let page = try decode(NotificationsPage.self, "notifications")
        #expect(page.total == 1)
        #expect(page.unread == 1)
        #expect(page.items[0].kind == "fare_drop")
        #expect(page.items[0].data["links"]["alerts"] == "/alerts?watch=1")
        #expect(page.items[0].readAt == nil)
        let empty = try JSONDecoder().decode(NotificationsPage.self, from: Data("{}".utf8))
        #expect(empty.items.isEmpty)
    }

    @Test func test_device() throws {
        let device = try decode(Device.self, "device")
        #expect(device.id == 12)
        #expect(device.platform == "ios")
    }

    @Test func test_nearbyV1AndV2() throws {
        let v1 = try decode(NearbyResponse.self, "nearby_v1")
        #expect(v1.place?.name == "Kyoto")
        #expect(v1.items?.count == 1)
        #expect(v1.sections == nil)
        let v2 = try decode(NearbyResponse.self, "nearby_v2")
        #expect(v2.sections?.map(\.id) == ["see", "eat", "shop", "stay"])
        #expect(v2.sections?[1].items.first?.placeId == "ChIJ1")
        #expect(v2.attribution == "Google Maps")
        #expect(v2.place?.region == nil)
    }

    @Test func test_liveCheck() throws {
        let result = try decode(LiveCheckResult.self, "live_check")
        #expect(result.kind == .hotel)
        #expect(result.quotes[0].amount == 412)
        #expect(result.sources.count == 1)
    }

    @Test func test_discoverAndCompare() throws {
        let discover = try decode(DiscoverResponse.self, "discover")
        #expect(discover.destinations[0].city == "Lisbon")
        #expect(discover.destinations[0].visaVerified == true)
        let compare = try decode(CompareSummary.self, "compare")
        #expect(compare.flight?.priceUsd == 620)
        #expect(compare.ease?.grade == "green")
        #expect(compare.estimate?.budgetStatus == "under")
    }

    @Test func test_importPreview() throws {
        let result = try decode(LinkImportResult.self, "import_preview")
        #expect(result.places[0].verified == true)
        #expect(result.destinations[0].airports == ["LIS", "CAT"])
        #expect(result.seasonHint == nil)
        #expect(result.suggestedDays == 3)
    }

    @Test func test_adminAndFeedback() throws {
        let entry = try decode(FeedbackEntry.self, "feedback_entry")
        #expect(entry.rating == 4)
        #expect(entry.metadata?["lang"] == "en")
        let summary = try decode(TelemetrySummary.self, "telemetry_summary")
        #expect(summary.days[0].events == 120)
        #expect(summary.topScreens[0].route == "/results")
        #expect(summary.users7d == 9)
    }

    @Test func test_healthAndClientConfig() throws {
        let health = try decode(Health.self, "health")
        #expect(health.serpapiConfigured == true)
        #expect(health.pushConfigured == false)
        let config = try decode(ClientConfig.self, "client_config")
        #expect(config.publicBaseURL == URL(string: "https://voyager.example"))
        #expect(config.telemetry == TelemetryRemoteConfig(enabled: true, flushIntervalS: 15, maxBatch: 50))
        #expect(config.features["social_login"] == false)
    }

    @Test func test_clientConfigToleratesPartialBody() throws {
        let config = try JSONDecoder().decode(ClientConfig.self, from: Data(#"{"public_base_url": null}"#.utf8))
        #expect(config.publicBaseURL == nil)
        #expect(config.telemetry.enabled == false)
        #expect(config.features.isEmpty)
    }

    @Test func test_numbersAsStringsAccepted() throws {
        let json = #"{"id": "4", "price": "150", "last_price": "150.5", "check_count": "3", "email_enabled": 1, "unknown": {"a": 1}}"#
        let watch = try JSONDecoder().decode(FareWatch.self, from: Data(json.utf8))
        #expect(watch.id == 4)
        #expect(watch.lastPrice == 150.5)
        #expect(watch.checkCount == 3)
        #expect(watch.emailEnabled == true)
        let hist = try JSONDecoder().decode(FareWatchHistoryPoint.self, from: Data(#"{"price": "150"}"#.utf8))
        #expect(hist.price == 150)
    }

    @Test func test_wrongTypesBecomeNilAndMissingRequiredThrows() throws {
        let watch = try JSONDecoder().decode(FareWatch.self, from: Data(#"{"id": 1, "last_price": "abc", "status": {"x": 1}}"#.utf8))
        #expect(watch.lastPrice == nil)
        #expect(watch.status == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FareWatch.self, from: Data(#"{"status": "active"}"#.utf8))
        }
    }
}
