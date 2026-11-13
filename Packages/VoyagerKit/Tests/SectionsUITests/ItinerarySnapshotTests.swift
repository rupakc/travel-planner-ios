import DesignSystem
import Domain
import SnapshotTesting
import SwiftUI
import VoyagerModel
import XCTest

@testable import SectionsUI

@MainActor
final class ItinerarySnapshotTests: XCTestCase {
    private let lean: [SnapshotConfig] = [.phoneLight, .phoneDark, .padLight, .padDark]

    private func editedSelections() -> JSONValue {
        let itinerary = ItineraryFixture.itinerary
        var layout = ItineraryLayout.moveSlot(itinerary, layout: nil, key: "1-evening", day: 2, timeOfDay: "evening")
        layout = ItineraryLayout.removeSlot(itinerary, layout: layout, key: "2-afternoon")
        var selections = Selections.empty.object ?? [:]
        selections["itinerary_layout"] = layout
        selections["itinerary_edits"] = ["1-morning": ["activity": "Torre de Belém", "cost": 20]]
        selections["itinerary_notes"] = ["1-morning": "Buy tickets online"]
        return .object(selections)
    }

    private func host(_ selections: JSONValue) -> ItineraryHost {
        ItineraryHost(
            itinerary: { ItineraryFixture.itinerary }, selections: { selections }, setSelections: { _ in },
            recheck: { _ in ["overall": "green", "findings": []] })
    }

    func test_itinerary() {
        assertSnapshots(
            of: {
                ItinerarySectionView(data: ItineraryFixture.itinerary, ctx: .inert)
            }, named: "plain", configs: lean)
    }

    func test_itineraryEditedGerman() {
        let selections = editedSelections()
        assertSnapshots(
            of: {
                ItinerarySectionView(
                    data: ItineraryFixture.itinerary,
                    ctx: SectionContext(
                        isSelected: { _, _ in false }, toggle: { _, _ in }, openURL: { _, _ in },
                        searchData: ["must_include": [["name": "Alfama"], ["name": "Sintra"]]]))
                .environment(\.itineraryHost, host(selections))
            }, named: "edited", configs: [.phoneLight, .padDark, .germanAX5])
    }

    func test_stressTest() {
        assertSnapshots(
            of: { StressTestSectionView(data: ItineraryFixture.findings, ctx: .inert) },
            named: "plain", configs: lean)
    }

    func test_stressTestAfterMoves() {
        let selections = editedSelections()
        assertSnapshots(
            of: {
                StressTestSectionView(data: ItineraryFixture.findings, ctx: .inert)
                    .environment(\.itineraryHost, host(selections))
            }, named: "moved", configs: [.phoneLight, .phoneDark])
    }

    func test_mapCollapsed() {
        assertSnapshots(
            of: { TripMapView(data: ItineraryFixture.itinerary, ctx: .inert) },
            named: "collapsed", configs: [.phoneLight, .phoneDark])
    }
}
