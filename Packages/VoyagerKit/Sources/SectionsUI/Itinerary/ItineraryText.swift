import Domain
import L10n
import VoyagerModel

/// Strings and small readers shared by the itinerary views.
enum ItineraryText {
    static func timeOfDay(_ value: String?) -> String {
        switch value {
        case "morning": L10n.text(K.itinerary.time.morning)
        case "afternoon": L10n.text(K.itinerary.time.afternoon)
        case "evening": L10n.text(K.itinerary.time.evening)
        default: value ?? ""
        }
    }

    static func position(day: JSONValue, timeOfDay tod: JSONValue) -> String {
        L10n.text(K.itinerary.position, ["day": dayNumberText(day), "time": timeOfDay(tod.string)])
    }

    static func dayNumberText(_ day: JSONValue) -> String {
        if let number = day.int { return String(number) }
        return day.string ?? ""
    }

    static func dayHeading(_ day: JSONValue) -> String {
        let number = dayNumberText(day["day_number"])
        if let city = day["city"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            return L10n.text(K.itinerary.day.headingCity, ["day": number, "city": city])
        }
        return L10n.text(K.itinerary.day.heading, ["day": number])
    }

    /// `"{{minutes}}"`-style templates stay whole: each argument is its own placeholder.
    static var transitStrings: Schedule.TransitStrings {
        let minutes = ["minutes": "{{minutes}}"]
        let both = ["minutes": "{{minutes}}", "km": "{{km}}"]
        return Schedule.TransitStrings(
            walk: L10n.text(K.itinerary.transit.walk, minutes),
            walkKm: L10n.text(K.itinerary.transit.walkKm, both),
            transit: L10n.text(K.itinerary.transit.transit, minutes))
    }

    static func usd(_ amount: Double) -> String {
        Fmt.currency(amount, code: "USD")
    }

    /// A finite, non-negative cost from loose JSON (number or numeric string); else nil.
    static func cost(_ value: JSONValue) -> Double? {
        guard let number = value.double, number.isFinite, number >= 0 else { return nil }
        return number
    }

    /// A cost typed by the user (`12`, `12.5`, `12,5`); empty or junk is nil.
    static func parseCost(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// The link-import summary line of the web `linkCoverageSummary`: how many wanted places made it in.
    struct LinkCoverage: Equatable {
        enum State { case pending, ready }
        var total: Int
        var inItinerary: Int
        var missing: [String]
        var state: State
    }

    static func linkCoverage(searchData: JSONValue?, itinerary: JSONValue) -> LinkCoverage? {
        let wanted = (searchData?["must_include"].array ?? []).compactMap { $0["name"].string }
        guard !wanted.isEmpty else { return nil }
        let days = itinerary["days"].array ?? []
        guard !days.isEmpty else { return LinkCoverage(total: wanted.count, inItinerary: 0, missing: [], state: .pending) }
        var linked = Set<String>()
        for day in days {
            for slot in day["slots"].array ?? [] where slot["from_link"].isTruthy {
                let places = (slot["link_places"].array ?? []).compactMap(\.string)
                if !places.isEmpty { linked.formUnion(places) } else if let one = slot["link_place"].string { linked.insert(one) }
            }
            for extra in day["link_extras"].array ?? [] { if let name = extra["name"].string { linked.insert(name) } }
        }
        let missing = wanted.filter { !linked.contains($0) }
        return LinkCoverage(total: wanted.count, inItinerary: wanted.count - missing.count, missing: missing, state: .ready)
    }
}
