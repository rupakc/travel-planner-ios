import L10n
import SwiftUI
import Testing
import VoyagerModel

@testable import SectionsUI

@MainActor
struct SectionRegistryTests {
    @Test func test_orderMatchesWebAgentOrder() {
        #expect(
            SectionID.allCases.map(\.rawValue) == [
                "flights", "weather", "hotels", "activities", "places_to_see", "walking_tours", "events", "visa", "sim",
                "tips", "emergency_card", "getting_around", "forex", "itinerary", "stress_test", "packing_list",
            ])
    }

    @Test func test_everyIDHasAView() {
        for id in SectionID.allCases {
            _ = SectionRegistry.view(for: id, data: .object([:]), ctx: .inert)
        }
        #expect(SectionID.allCases.count == 16)
    }

    @Test func test_everyIDHasATitleAndUnavailableCopy() {
        for id in SectionID.allCases {
            #expect(!id.title.isEmpty && !id.title.contains("."), "\(id)")
            #expect(!L10n.text(id.unavailableKey).isEmpty)
        }
        #expect(SectionID.flights.title == "Flights")
        #expect(SectionID.stressTest.title == "Trip Health Check")
    }

    @Test func test_genericItemsFindsTheMainList() {
        let data: JSONValue = .object(["results": .array([.object(["name": .string("A")])])])
        #expect(GenericSectionView.items(in: data).first?.name == "A")
        #expect(GenericSectionView.items(in: .object(["error": .string("x")])).isEmpty)
        let other: JSONValue = .object(["days": .array([.object(["title": .string("Day 1")])])])
        #expect(GenericSectionView.items(in: other).first?.name == "Day 1")
    }
}
