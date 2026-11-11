import Foundation

/// An optional surface that can be shown or hidden per traveller type. Core surfaces (Search, Results, My Plan,
/// Settings) are never hidden and are not listed. `id` is the stable string stored in the user's overrides.
public struct AppFeature: Sendable, Hashable, Identifiable {
    public let id: String
    public let iconName: String
    public let defaultOnFor: Set<TravellerType>

    /// Localisation keys: `feature_<id>_title` and `feature_<id>_description`.
    public var titleKey: String { "feature_\(id)_title" }
    public var descriptionKey: String { "feature_\(id)_description" }
}

/// The feature catalogue (Android `DefaultFeatureCatalogue`): every feature in display order with the traveller
/// types it is on by default for.
public enum FeatureCatalogue {
    private static let everyone = Set(TravellerType.allCases)

    public static let all: [AppFeature] = [
        AppFeature(id: "chat", iconName: "chat", defaultOnFor: everyone),
        AppFeature(id: "visa_checker", iconName: "verified", defaultOnFor: everyone),
        AppFeature(id: "deal_alerts", iconName: "notifications", defaultOnFor: [.budgetBackpacker, .family, .business]),
        AppFeature(id: "best_value", iconName: "thumb_up", defaultOnFor: [.budgetBackpacker, .family]),
        AppFeature(id: "budget_planner", iconName: "wallet", defaultOnFor: [.budgetBackpacker, .family]),
        AppFeature(id: "compare", iconName: "compare", defaultOnFor: [.budgetBackpacker, .cultureFoodie, .relaxation, .luxury]),
        AppFeature(id: "surprise_me", iconName: "surprise", defaultOnFor: [.budgetBackpacker, .adventure, .cultureFoodie, .relaxation]),
        AppFeature(id: "import_link", iconName: "link", defaultOnFor: [.adventure, .cultureFoodie, .luxury]),
        AppFeature(id: "near_me", iconName: "near_me", defaultOnFor: [.budgetBackpacker, .adventure, .cultureFoodie, .business]),
        AppFeature(
            id: "itinerary_editor", iconName: "edit_calendar",
            defaultOnFor: [.family, .luxury, .cultureFoodie, .business, .relaxation]),
        AppFeature(id: "walking_tours", iconName: "walk", defaultOnFor: [.budgetBackpacker, .cultureFoodie]),
        AppFeature(id: "events", iconName: "event", defaultOnFor: [.budgetBackpacker, .luxury, .cultureFoodie]),
        AppFeature(id: "packing_list", iconName: "luggage", defaultOnFor: [.family, .adventure, .relaxation, .accessible]),
        AppFeature(id: "emergency_card", iconName: "emergency", defaultOnFor: [.family, .adventure, .accessible]),
        AppFeature(id: "trip_health_check", iconName: "health", defaultOnFor: [.family, .luxury, .business, .accessible]),
        AppFeature(id: "forex", iconName: "currency", defaultOnFor: [.budgetBackpacker, .luxury, .business]),
        AppFeature(id: "sim", iconName: "sim", defaultOnFor: [.budgetBackpacker, .adventure, .business]),
        AppFeature(id: "accessibility_info", iconName: "accessibility", defaultOnFor: [.accessible]),
    ]

    /// Ids switched on by default for any of `types`, in catalogue order.
    public static func defaults(for types: [TravellerType]) -> [String] {
        all.filter { feature in types.contains { feature.defaultOnFor.contains($0) } }.map(\.id)
    }

    /// visible = defaults(types) ∪ enabled − disabled. Ids that are not catalogue features are ignored, and a
    /// disable wins over an enable.
    public static func visible(types: [TravellerType], enabled: Set<String>, disabled: Set<String>) -> Set<String> {
        let known = Set(all.map(\.id))
        return (Set(defaults(for: types)).union(enabled.intersection(known))).subtracting(disabled)
    }
}
