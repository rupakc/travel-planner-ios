import DesignSystem
import L10n

/// The sixteen section tiles, in the web's `AGENT_ORDER`. `confidence` and `pricing_advisor` are separate
/// events with their own views, not tiles.
public enum SectionID: String, CaseIterable, Sendable, Identifiable {
    case flights, weather, hotels, activities
    case places_to_see, walking_tours, events, visa, sim, tips
    case emergency_card, getting_around, forex, itinerary, stress_test, packing_list

    public var id: String { rawValue }

    /// The localised title (`results:agents.<id>.label`, the web's section header text).
    public var title: String {
        L10n.text(titleKey)
    }

    var titleKey: LKey {
        switch self {
        case .flights: K.results.agents.flights.label
        case .weather: K.results.agents.weather.label
        case .hotels: K.results.agents.hotels.label
        case .activities: K.results.agents.activities.label
        case .places_to_see: K.results.agents.places_to_see.label
        case .walking_tours: K.results.agents.walking_tours.label
        case .events: K.results.agents.events.label
        case .visa: K.results.agents.visa.label
        case .sim: K.results.agents.sim.label
        case .tips: K.results.agents.tips.label
        case .emergency_card: K.results.agents.emergency_card.label
        case .getting_around: K.results.agents.getting_around.label
        case .forex: K.results.agents.forex.label
        case .itinerary: K.results.agents.itinerary.label
        case .stress_test: K.results.agents.stress_test.label
        case .packing_list: K.results.agents.packing_list.label
        }
    }

    /// The copy for a section whose AI call failed and left no data: the web's per-section "unavailable" line
    /// where it has one, else the generic error.
    var unavailableKey: LKey {
        switch self {
        case .visa: K.results.visa.unavailable
        case .forex: K.results.forex.unavailable
        case .emergency_card: K.sections.emergency.unavailable
        case .packing_list: K.sections.packing.unavailable
        case .stress_test: K.sections.stress.unavailable
        default: K.errors.generic
        }
    }

    /// SF Symbol for the header (the web uses lucide icons of the same meaning).
    var symbol: String {
        switch self {
        case .flights: "airplane"
        case .weather: "cloud.sun"
        case .hotels: "bed.double"
        case .activities: "figure.hiking"
        case .places_to_see: "mappin.and.ellipse"
        case .walking_tours: "figure.walk"
        case .events: "ticket"
        case .visa: "doc.text"
        case .sim: "simcard"
        case .tips: "lightbulb"
        case .emergency_card: "cross.case"
        case .getting_around: "tram"
        case .forex: "dollarsign.circle"
        case .itinerary: "calendar"
        case .stress_test: "checkmark.shield"
        case .packing_list: "suitcase"
        }
    }
}
