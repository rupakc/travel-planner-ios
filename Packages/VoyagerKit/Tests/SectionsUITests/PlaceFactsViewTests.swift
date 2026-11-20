import Domain
import L10n
import SwiftUI
import Testing
import VoyagerModel

@testable import SectionsUI

@MainActor
struct PlaceFactsViewTests {
    private static let berlin = PlaceFacts.Place(key: "city:1", name: "Berlin", scope: "city", groups: [:])

    @Test func groupTabsUseTheCatalogue() {
        #expect(PlaceFactsSectionView.groupTitle("historical") == "Historical")
        #expect(PlaceFactsSectionView.groupTitle("little_known") == "Little-known")
        #expect(PlaceFacts.factTypes.allSatisfy { !PlaceFactsSectionView.groupTitle($0).contains(".") })
    }

    @Test func placeChipNamesTheScope() {
        #expect(PlaceFactsSectionView.placeTitle(Self.berlin) == "Berlin · City")
        var odd = Self.berlin
        odd.scope = "galaxy"
        #expect(PlaceFactsSectionView.placeTitle(odd) == "Berlin", "an unknown scope is left out")
        #expect(PlaceFactsSectionView.scopeTitle("country") == "Country")
        #expect(PlaceFactsSectionView.scopeTitle(nil) == nil)
    }

    @Test func factsSectionHasTitleAndIcon() {
        #expect(SectionID.facts.title == "Place Facts")
        #expect(SectionID.facts.isOptional)
        _ = SectionRegistry.view(for: .facts, data: .object([:]), ctx: .inert)
    }

    @Test func selectionIsLookedUpInThePlanField() throws {
        let fact = try #require(PlaceFacts.fact(["id": "a:1", "text": "A fact.", "origin": "ai"]))
        let ctx = SectionContext(
            isSelected: { field, item in field == "place_facts" && item["id"] == "a:1" },
            toggle: { _, _ in }, openURL: { _, _ in })
        let item = PlaceFacts.selection(fact, placeName: "Berlin")
        #expect(ctx.isSelected(PlaceFacts.selectionField, item))
        #expect(item["place"] == "Berlin")
    }
}
