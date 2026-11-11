import SwiftUI

/// The family each result section is tinted with (stop 600 in light, the dark remap in dark).
public enum SectionAccent {
    public static func family(for section: String) -> Family {
        switch section {
        case "flights", "weather": .sky
        case "hotels": .violet
        case "activities", "forex": .emerald
        case "places_to_see": .lime
        case "walking_tours", "itinerary", "packing_list": .teal
        case "events": .fuchsia
        case "visa", "tips": .amber
        case "sim", "stress_test": .rose
        case "getting_around": .cyan
        case "emergency_card": .red
        default: .primary
        }
    }

    public static func color(for section: String) -> Color {
        Palette.color(family(for: section), .s600)
    }
}
