import Foundation
import VoyagerModel

/// Plain-text plan for "Share as text" (the phone's take on the web's Print / PDF page): the plan name, a trip
/// summary, each selected item with its own price and only http(s) links, the day-by-day itinerary (arranged and
/// timed like the web), and the share link when there is one. Never adds a number the plan does not contain.
///
/// Port of Android's `PlanShareText`, reading the web's selections shape (`flight`, `flights`, `hotel`,
/// `activities`, `places_to_see`, `walking_tours`, `events`, `sim`, `getting_around`, `tips`, `itinerary*`).
public enum PlanShareText {
    /// Headings and money format, from the localised catalogue (domain code holds no UI copy and no default
    /// language). `english` is for tests and previews only.
    public struct Labels: Sendable {
        public let flights: String
        public let hotel: String
        public let activities: String
        public let places: String
        public let walkingTours: String
        public let events: String
        public let sim: String
        public let gettingAround: String
        public let tips: String
        public let itinerary: String
        public let estimate: String
        public let morning: String
        public let afternoon: String
        public let evening: String
        public let day: @Sendable (Int) -> String
        public let perNight: @Sendable (String) -> String
        public let viewOnline: @Sendable (String) -> String
        /// Currency text for a USD amount.
        public let formatPrice: @Sendable (Double) -> String

        public init(
            flights: String, hotel: String, activities: String, places: String, walkingTours: String,
            events: String, sim: String, gettingAround: String, tips: String, itinerary: String,
            estimate: String, morning: String, afternoon: String, evening: String,
            day: @escaping @Sendable (Int) -> String,
            perNight: @escaping @Sendable (String) -> String,
            viewOnline: @escaping @Sendable (String) -> String,
            formatPrice: @escaping @Sendable (Double) -> String
        ) {
            self.flights = flights
            self.hotel = hotel
            self.activities = activities
            self.places = places
            self.walkingTours = walkingTours
            self.events = events
            self.sim = sim
            self.gettingAround = gettingAround
            self.tips = tips
            self.itinerary = itinerary
            self.estimate = estimate
            self.morning = morning
            self.afternoon = afternoon
            self.evening = evening
            self.day = day
            self.perNight = perNight
            self.viewOnline = viewOnline
            self.formatPrice = formatPrice
        }

        /// English copy and en-US prices, for tests and previews only.
        public static let english = Labels(
            flights: "Flights", hotel: "Hotel", activities: "Activities", places: "Places",
            walkingTours: "Free walking tours", events: "Events", sim: "SIM", gettingAround: "Getting around",
            tips: "Tips", itinerary: "Itinerary", estimate: "Estimate",
            morning: "Morning", afternoon: "Afternoon", evening: "Evening",
            day: { "Day \($0)" }, perNight: { "\($0) / night" }, viewOnline: { "View the plan: \($0)" },
            formatPrice: { ExportText.usd($0) }
        )

        func timeOfDay(_ raw: JSONValue) -> String? {
            switch raw.string {
            case "morning": return morning
            case "afternoon": return afternoon
            case "evening": return evening
            default: return nil
            }
        }
    }

    public static func text(
        planName: String,
        searchData: JSONValue,
        selections: JSONValue,
        shareURL: String?,
        labels: Labels
    ) -> String {
        var out: [String] = [planName]
        out += summaryLines(searchData)
        out += sectionLines(selections, labels)
        out += itineraryLines(selections, labels)
        if let shareURL = ExportText.safeURL(shareURL) {
            out.append("")
            out.append(labels.viewOnline(shareURL))
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sectionLines(_ selections: JSONValue, _ labels: Labels) -> [String] {
        var out: [String] = []
        func section(_ title: String, _ items: [JSONValue], _ line: (JSONValue) -> String) {
            let lines = items.map(line).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else { return }
            out.append("")
            out.append(title)
            out += lines.map { "  \u{2022} \($0)" }
        }
        let single = { (value: JSONValue) -> [JSONValue] in value.isTruthy ? [value] : [] }

        section(labels.flights, single(selections["flight"]) + (selections["flights"].array ?? [])) {
            flightLine($0, labels) + link($0["booking_url"])
        }
        section(labels.hotel, single(selections["hotel"])) { hotel in
            let nightly = hotel["price_per_night_usd"]
            let perNight = ExportText.isPositive(nightly) ? labels.perNight(labels.formatPrice(nightly.double ?? 0)) : nil
            return ExportText.joined([text(hotel["name"]), text(hotel["location"]), perNight], ", ") + link(hotel["booking_url"])
        }
        section(labels.activities, selections["activities"].array ?? []) {
            named($0["name"], $0["price_usd"], labels) + link($0["booking_url"])
        }
        section(labels.places, selections["places_to_see"].array ?? []) {
            named($0["name"], $0["admission_fee_usd"], labels) + link($0["info_url"])
        }
        section(labels.walkingTours, selections["walking_tours"].array ?? []) { (text($0["name"]) ?? "") + link($0["url"]) }
        section(labels.events, selections["events"].array ?? []) { event in
            var dates: [String] = []
            for key in ["start_date", "end_date"] {
                if let value = text(event[key]), !dates.contains(value) { dates.append(value) }
            }
            return ExportText.joined([text(event["name"]), dates.isEmpty ? nil : dates.joined(separator: " \u{2013} ")], ", ")
        }
        section(labels.sim, single(selections["sim"])) { sim in
            let provider = ExportText.joined([text(sim["provider"]), text(sim["plan_name"])], " ")
            return named(.string(provider), sim["price_usd"], labels) + link(sim["url"])
        }
        section(labels.gettingAround, selections["getting_around"].array ?? []) {
            ExportText.joined([text($0["name"]), text($0["price_info"])], ", ") + link($0["booking_url"])
        }
        section(labels.tips, selections["tips"].array ?? []) { text($0["title"]) ?? "" }
        return out
    }

    private static func itineraryLines(_ selections: JSONValue, _ labels: Labels) -> [String] {
        let days = PlanICS.planItineraryDays(selections: selections, itinerary: nil)
        guard !days.isEmpty else { return [] }
        var out = ["", labels.itinerary]
        for day in days {
            out.append(ExportText.joined([
                day["day_number"].int.map(labels.day), text(day["date"]), text(day["city"]), text(day["theme"]),
            ], ", "))
            for slot in day["slots"].array ?? [] {
                let key = text(slot["key"])
                let edited = key.flatMap { text(selections["itinerary_edits"][$0]["activity"]) }
                guard let activity = edited ?? text(slot["activity"]) else { continue }
                let range = text(slot["start_time"]).flatMap { start in text(slot["end_time"]).map { "\(start)\u{2013}\($0)" } }
                let note = key.flatMap { text(selections["itinerary_notes"][$0]) }
                let parts = [range ?? labels.timeOfDay(slot["time_of_day"]), activity, text(slot["location"])]
                out.append("  \u{2022} " + ExportText.joined(parts, " \u{00B7} "))
                if let note { out.append("    \(note)") }
            }
        }
        return out
    }

    // MARK: - Lines

    private static func summaryLines(_ searchData: JSONValue) -> [String] {
        var lines: [String] = []
        if let origin = text(searchData["origin"]), let destination = text(searchData["destination"]) {
            lines.append("\(origin) \u{2192} \(destination)")
        }
        let dates = ExportText.joined([text(searchData["departure_date"]), text(searchData["return_date"])], " \u{2013} ")
        if !dates.isEmpty { lines.append(dates) }
        return lines
    }

    private static func flightLine(_ flight: JSONValue, _ labels: Labels) -> String {
        let leg = ExportText.or(flight["outbound"], flight)
        let route: String
        if let origin = text(leg["origin"]), let destination = text(leg["destination"]) {
            route = "\(origin) \u{2192} \(destination)"
        } else {
            route = [flight["leg_from"], flight["leg_to"]].compactMap { text($0) }
                .map { $0.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? $0 }
                .joined(separator: " \u{2192} ")
        }
        var price: String?
        if ExportText.isPositive(flight["price_usd"]) {
            let amount = labels.formatPrice(flight["price_usd"].double ?? 0)
            let estimated = flight["is_estimate"].bool == true || flight["source"].string == "estimate"
            price = estimated ? "\(amount) (\(labels.estimate))" : amount
        }
        return ExportText.joined([
            ExportText.joined([text(leg["airline"]), text(leg["flight_number"])], " "),
            route,
            ExportText.joined([text(ExportText.or(leg["departure_date"], flight["leg_date"])), text(leg["departure_time"])], " "),
            price,
        ], " \u{00B7} ")
    }

    private static func named(_ name: JSONValue, _ price: JSONValue, _ labels: Labels) -> String {
        ExportText.joined([
            text(name),
            ExportText.isPositive(price) ? labels.formatPrice(price.double ?? 0) : nil,
        ], ", ")
    }

    private static func link(_ url: JSONValue) -> String {
        ExportText.safeURL(url.string).map { "\n    \($0)" } ?? ""
    }

    /// A non-empty display string, or `nil`.
    private static func text(_ value: JSONValue) -> String? {
        guard value.isTruthy else { return nil }
        let string = ExportText.js(value)
        return string.trimmingCharacters(in: .whitespaces).isEmpty ? nil : string
    }
}
