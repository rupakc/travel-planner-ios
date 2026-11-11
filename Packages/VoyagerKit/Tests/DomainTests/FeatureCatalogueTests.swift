import Testing
@testable import Domain

/// The cases of Android's `FeatureCatalogueTest`.
@Suite struct FeatureCatalogueTests {
    private let expectedIDs = [
        "deal_alerts", "best_value", "budget_planner", "compare", "surprise_me", "import_link", "chat", "near_me",
        "packing_list", "emergency_card", "walking_tours", "events", "visa_checker", "forex", "sim", "trip_health_check",
        "itinerary_editor", "accessibility_info",
    ]

    @Test func catalogueHoldsExactlyTheAndroidFeatures() {
        #expect(Set(FeatureCatalogue.all.map(\.id)) == Set(expectedIDs))
        #expect(FeatureCatalogue.all.count == expectedIDs.count)
        for feature in FeatureCatalogue.all {
            #expect(feature.titleKey == "feature_\(feature.id)_title")
            #expect(feature.descriptionKey == "feature_\(feature.id)_description")
            #expect(!feature.iconName.isEmpty)
            #expect(!feature.defaultOnFor.isEmpty, "\(feature.id) is on for nobody")
        }
    }

    @Test func everyTypeGetsAUsefulDefaultSet() {
        for type in TravellerType.allCases {
            let defaults = FeatureCatalogue.defaults(for: [type])
            #expect(defaults.count >= 3, "\(type) has \(defaults.count)")
            #expect(defaults.contains("chat"))
        }
    }

    @Test func defaultsForSeveralTypesAreTheUnion() {
        let family = Set(FeatureCatalogue.defaults(for: [.family]))
        let accessible = Set(FeatureCatalogue.defaults(for: [.accessible]))
        #expect(Set(FeatureCatalogue.defaults(for: [.family, .accessible])) == family.union(accessible))
        #expect(accessible.contains("accessibility_info"))
        #expect(!family.contains("accessibility_info"))
        #expect(FeatureCatalogue.defaults(for: []).isEmpty)
    }

    @Test func defaultsKeepCatalogueOrder() {
        #expect(FeatureCatalogue.defaults(for: TravellerType.allCases) == FeatureCatalogue.all.map(\.id))
    }

    @Test func visibleIsDefaultsUnionEnabledMinusDisabled() {
        let defaults = Set(FeatureCatalogue.defaults(for: [.business]))
        #expect(defaults.contains("sim"))
        #expect(!defaults.contains("walking_tours"))
        let visible = FeatureCatalogue.visible(types: [.business], enabled: ["walking_tours"], disabled: ["sim"])
        #expect(visible == defaults.union(["walking_tours"]).subtracting(["sim"]))
    }

    @Test func disabledWinsOverEnabledAndUnknownIDsAreIgnored() {
        let visible = FeatureCatalogue.visible(types: [.luxury], enabled: ["sim", "search", "bogus"], disabled: ["sim", "settings"])
        #expect(visible == Set(FeatureCatalogue.defaults(for: [.luxury])).subtracting(["sim"]))
    }

    @Test func androidDefaultsForKeyTypes() {
        #expect(Set(FeatureCatalogue.defaults(for: [.budgetBackpacker])) == [
            "chat", "visa_checker", "deal_alerts", "best_value", "budget_planner", "compare", "surprise_me", "near_me",
            "walking_tours", "events", "forex", "sim",
        ])
        #expect(Set(FeatureCatalogue.defaults(for: [.accessible])) == [
            "chat", "visa_checker", "packing_list", "emergency_card", "trip_health_check", "accessibility_info",
        ])
    }
}
