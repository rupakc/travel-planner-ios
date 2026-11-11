import Foundation

/// Default plan names, "The <adjective> <destination> <noun>" (port of `generatePlanName`).
public enum PlanName {
    static let themes: [String: [String]] = [
        "food": ["Foodie", "Culinary", "Gourmet", "Tasty"],
        "history": ["Historic", "Ancient", "Timeless", "Heritage"],
        "adventure": ["Wild", "Epic", "Daring", "Thrilling"],
        "culture": ["Cultural", "Artistic", "Vibrant", "Soulful"],
        "nature": ["Green", "Natural", "Serene", "Wilderness"],
        "shopping": ["Shopaholic", "Boutique", "Bazaar", "Market"],
        "nightlife": ["Midnight", "Neon", "After-Dark", "Starlit"],
        "wellness": ["Zen", "Blissful", "Peaceful", "Tranquil"],
        "art": ["Artsy", "Creative", "Gallery", "Canvas"],
        "family": ["Family", "Joyful", "Sunny", "Playful"],
    ]

    static let nouns = [
        "Adventure", "Escape", "Journey", "Odyssey", "Expedition", "Quest", "Voyage", "Getaway", "Trail", "Safari",
    ]

    static let seasonal: [String: [String]] = [
        "spring": ["Blossom", "Fresh", "Springtime"],
        "summer": ["Sunny", "Sizzling", "Tropical"],
        "fall": ["Golden", "Autumn", "Amber"],
        "winter": ["Frosty", "Cozy", "Snowbound"],
    ]

    static let generic = ["Grand", "Dreamy", "Cosmic", "Wanderlust"]

    /// Northern-hemisphere season of an ISO date; an unreadable date is "winter" (the web's `NaN` falls through).
    static func season(_ date: String?) -> String? {
        guard let date, !date.isEmpty else { return nil }
        let ms = PlanJS.ms(.string(date))
        guard !ms.isNaN else { return "winter" }
        let month = PlanJS.civil(fromDays: Int((ms / PlanJS.dayMs).rounded(.down))).month
        switch month {
        case 3...5: return "spring"
        case 6...8: return "summer"
        case 9...11: return "fall"
        default: return "winter"
        }
    }

    public static func generate(
        destination: String, interests: [String] = [], departureDate: String? = nil,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let adjectives: [String]
        if let first = interests.first, let themed = themes[first] {
            adjectives = themed
        } else if let season = season(departureDate) {
            adjectives = seasonal[season] ?? generic
        } else {
            adjectives = generic
        }
        let adjective = adjectives.randomElement(using: &generator) ?? "Grand"
        let noun = nouns.randomElement(using: &generator) ?? "Adventure"
        return "The \(adjective) \(destination.isEmpty ? "Mystery" : destination) \(noun)"
    }

    public static func generate(destination: String, interests: [String] = [], departureDate: String? = nil) -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(destination: destination, interests: interests, departureDate: departureDate, using: &generator)
    }
}
