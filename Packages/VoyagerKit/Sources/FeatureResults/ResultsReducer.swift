import Foundation
import L10n
import SectionsUI
import VoyagerModel

/// One section tile's state: its progress and the latest payload (nil until the first event).
public struct SectionEntry: Equatable, Sendable {
    public var status: SectionStatus
    public var data: JSONValue?

    public init(status: SectionStatus, data: JSONValue? = nil) {
        self.status = status
        self.data = data
    }

    /// The payload is the backend's `{"error": ...}` rather than a result.
    public var isErrorData: Bool { data.map(ResultsReducer.isError) ?? false }

    /// A usable payload (present, not an error).
    public var hasGoodData: Bool { data != nil && !isErrorData }
}

/// Everything the Results screen shows, as the web's `statuses` / `results` / `confidenceData` / `pricingData`.
public struct ResultsState: Equatable, Sendable {
    public var sections: [SectionID: SectionEntry]
    public var confidence: JSONValue?
    public var pricing: JSONValue?
    public var done: Bool
    /// The search (a `TravelSearchRequest`-shaped object): input of the client itinerary fallback.
    public var searchData: JSONValue?
    /// The plain "AI paused" banner text (`ai_limit` / `ai_billing`), shown once instead of N failures.
    public var banner: String?

    /// The web's initial statuses: the 13 phase-1 sections `loading`; itinerary, stress test and packing list `waiting`.
    public init(searchData: JSONValue? = nil) {
        var initial: [SectionID: SectionEntry] = [:]
        for id in SectionID.allCases {
            initial[id] = SectionEntry(status: Self.waitingIDs.contains(id) ? .waiting : .loading)
        }
        sections = initial
        confidence = nil
        pricing = nil
        done = false
        self.searchData = searchData
        banner = nil
    }

    static let waitingIDs: Set<SectionID> = [.itinerary, .stressTest, .packingList]

    public func status(_ id: SectionID) -> SectionStatus { sections[id]?.status ?? .waiting }
    public func data(_ id: SectionID) -> JSONValue? { sections[id]?.data }

    /// Sections with a usable result.
    public var readyCount: Int { sections.values.filter(\.hasGoodData).count }
    /// Sections whose payload is an error.
    public var errorCount: Int { sections.values.filter(\.isErrorData).count }
    /// The web's "done or enhancing" count.
    public var completedCount: Int { sections.values.filter { $0.status.isReady }.count }

    /// Section type → payload of every usable result: what `env.plan.latestResults` holds.
    public var latestResults: JSONValue {
        var object: [String: JSONValue] = [:]
        for (id, entry) in sections where entry.hasGoodData {
            if let data = entry.data { object[id.rawValue] = data }
        }
        return .object(object)
    }
}

/// The web status machine (api-contract section 3.2) as a pure function over the stream.
public enum ResultsReducer {
    public static func reduce(_ state: ResultsState, _ event: SearchStreamEvent) -> ResultsState {
        switch event {
        case .done:
            return finalized(state)
        case .agentStatus, .unknown:
            return state
        case .section(let type, let source, let data):
            return apply(state, type: type, source: source, data: data)
        }
    }

    // MARK: - Events

    private static func apply(_ state: ResultsState, type: String, source: SectionSource?, data: JSONValue) -> ResultsState {
        var next = state
        switch type {
        case "confidence":
            if !isError(data) { next.confidence = data }
            return next
        case "pricing_advisor":
            if !isError(data) { next.pricing = data }
            return next
        default:
            // Anything else that is not a tile is ignored, for forward compatibility.
            guard let id = SectionID(rawValue: type) else { return state }
            if let banner = pausedBanner(data) { next.banner = banner }
            next.sections[id] = entry(after: state.sections[id], source: source, data: data)
            advanceDependents(&next)
            return next
        }
    }

    /// The text of an `ai_limit` / `ai_billing` error: one plain banner instead of N failures.
    private static func pausedBanner(_ data: JSONValue) -> String? {
        guard let code = data["error_code"].string, code == "ai_limit" || code == "ai_billing" else { return nil }
        guard let message = data["error"].string, !message.isEmpty else { return nil }
        return message
    }

    /// The section's entry after one event: an AI error never replaces good data (the static table stays).
    private static func entry(after existing: SectionEntry?, source: SectionSource?, data: JSONValue) -> SectionEntry {
        guard isError(data) else { return SectionEntry(status: source == .static ? .enhancing : .done, data: data) }
        if source == .ai, let existing, existing.hasGoodData { return SectionEntry(status: .done, data: existing.data) }
        return SectionEntry(status: .error(data["error"].string ?? ""), data: data)
    }

    /// Itinerary starts once its two inputs are in; the stress test audits the finished itinerary.
    private static func advanceDependents(_ state: inout ResultsState) {
        if settled(state, .activities), settled(state, .hotels), state.status(.itinerary) == .waiting {
            state.sections[.itinerary]?.status = .loading
        }
        if state.status(.itinerary) == .done, state.status(.stressTest) == .waiting {
            state.sections[.stressTest]?.status = .loading
        }
    }

    /// The web's `done || enhancing` (an error result counts as finished too).
    private static func settled(_ state: ResultsState, _ id: SectionID) -> Bool {
        switch state.status(id) {
        case .done, .enhancing, .error: true
        default: false
        }
    }

    /// Stream end: pending verification cleared, the client itinerary if none arrived, every unfinished section `done`.
    static func finalized(_ state: ResultsState) -> ResultsState {
        var next = state
        for (id, entry) in state.sections {
            if let data = entry.data { next.sections[id]?.data = clearingPending(data) }
        }
        let itinerary = next.sections[.itinerary]?.data
        if !(itinerary?["days"].array?.isEmpty == false),
            let fallback = clientItinerary(
                activities: next.sections[.activities]?.data, hotels: next.sections[.hotels]?.data, searchData: next.searchData)
        {
            next.sections[.itinerary] = SectionEntry(status: .done, data: fallback)
        }
        for (id, entry) in next.sections {
            switch entry.status {
            case .waiting, .loading, .enhancing: next.sections[id]?.status = .done
            case .done, .error: break
            }
        }
        next.done = true
        return next
    }

    static func isError(_ data: JSONValue) -> Bool {
        data["error"].isTruthy
    }

    /// A section still awaiting link enrichment must not show "Checking..." forever.
    private static func clearingPending(_ data: JSONValue) -> JSONValue {
        guard case .object(var object) = data, case .object(var verification) = object["verification"] ?? .null,
            verification["pending"] == .bool(true)
        else { return data }
        verification["pending"] = .bool(false)
        object["verification"] = .object(verification)
        return .object(object)
    }

    // MARK: - Client itinerary (the web's `buildClientItinerary`)

    private static let day: TimeInterval = 86400

    /// A template itinerary from activities + hotels, for a stream that ended without one. Multi-city day labels
    /// and `must_include` placement are not ported (the server's own itinerary carries them).
    static func clientItinerary(activities: JSONValue?, hotels: JSONValue?, searchData: JSONValue?) -> JSONValue? {
        guard let searchData, !searchData.isNull, let departure = parse(searchData["departure_date"].string) else { return nil }
        let nights: Int
        if let returnDate = parse(searchData["return_date"].string) {
            nights = Int((returnDate.timeIntervalSince(departure) / day).rounded(.toNearestOrAwayFromZero))
        } else {
            nights = 7
        }
        var places = ItineraryPlaces(
            activities: (activities?["results"].array ?? []).filter { !$0["error"].isTruthy },
            hotel: text(hotels?["results"][0]["name"]) ?? L10n.text(K.sections.clientItinerary.yourHotel),
            dest: text(searchData["destination"]) ?? L10n.text(K.sections.clientItinerary.yourDestination))
        let themes = dayThemes(nights: nights)
        var days: [JSONValue] = []
        var total = 0.0
        for number in 1...max(1, nights + 1) {
            let slots: [JSONValue]
            if number == 1 {
                slots = places.arrivalSlots()
            } else if number == nights + 1 {
                slots = places.departureSlots()
            } else {
                slots = places.exploringSlots()
            }
            let daily = slots.reduce(0.0) { $0 + ($1["estimated_cost_usd"].double ?? 0) }
            total += daily
            days.append(
                .object([
                    "day_number": .number(Double(number)),
                    "date": .string(format(departure.addingTimeInterval(Double(number - 1) * day))),
                    "theme": .string(themes[min(number - 1, themes.count - 1)]),
                    "slots": .array(slots),
                    "daily_estimated_cost_usd": .number(daily),
                ]))
        }
        return .object([
            "days": .array(days),
            "total_estimated_cost_usd": .number(total.rounded(.toNearestOrAwayFromZero)),
            "source": .string("template"),
        ])
    }

    private static func dayThemes(nights: Int) -> [String] {
        let tc = K.sections.clientItinerary.self
        var themes = [L10n.text(tc.themeArrival)]
        if nights > 1 {
            for index in 0..<(nights - 1) { themes.append(L10n.text(tc.themeDay, ["n": String(index + 2)])) }
        }
        themes.append(L10n.text(tc.themeDeparture))
        return themes
    }

    /// What the template's days are made of: the activities not yet used, the first hotel and the destination.
    private struct ItineraryPlaces {
        let activities: [JSONValue]
        let hotel: String
        let dest: String
        private var used = 0

        init(activities: [JSONValue], hotel: String, dest: String) {
            self.activities = activities
            self.hotel = hotel
            self.dest = dest
        }

        private func slot(_ time: String, _ activity: String, _ location: String, _ hours: Double, _ notes: String, _ cost: Double)
            -> JSONValue
        {
            .object([
                "time_of_day": .string(time), "activity": .string(activity), "location": .string(location),
                "duration_hours": .number(hours), "notes": .string(notes), "estimated_cost_usd": .number(cost),
            ])
        }

        func arrivalSlots() -> [JSONValue] {
            let tc = K.sections.clientItinerary.self
            return [
                slot("morning", L10n.text(tc.arrive, ["dest": dest, "hotel": hotel]), dest, 3, L10n.text(tc.arriveNote), 30),
                slot("afternoon", L10n.text(tc.checkIn, ["hotel": hotel]), dest, 3, L10n.text(tc.checkInNote), 20),
                slot("evening", L10n.text(tc.welcomeDinner), dest, 2, L10n.text(tc.welcomeNote), 40),
            ]
        }

        func departureSlots() -> [JSONValue] {
            let tc = K.sections.clientItinerary.self
            return [
                slot("morning", L10n.text(tc.finalBreakfast), dest, 2, L10n.text(tc.finalNote), 25),
                slot("afternoon", L10n.text(tc.checkOut, ["hotel": hotel]), dest, 3, L10n.text(tc.checkOutNote), 25),
                slot("evening", L10n.text(tc.departureFlight), L10n.text(tc.airport), 3, L10n.text(tc.safeTravels), 0),
            ]
        }

        /// Morning, afternoon, evening from the next three activities; free time once they run out.
        mutating func exploringSlots() -> [JSONValue] {
            let tc = K.sections.clientItinerary.self
            var slots: [JSONValue] = []
            for time in ["morning", "afternoon", "evening"] {
                guard used < activities.count else {
                    slots.append(slot(time, L10n.text(tc.freeTime, ["dest": dest]), dest, 3, L10n.text(tc.freeNote), 30))
                    continue
                }
                let activity = activities[used]
                used += 1
                let hours = activity["duration_hours"].double.flatMap { $0 != 0 ? $0 : nil } ?? 2
                let price = activity["price_usd"].double.flatMap { $0 != 0 && $0.isFinite ? $0 : nil } ?? 25
                slots.append(
                    slot(
                        time, ResultsReducer.text(activity["name"]) ?? L10n.text(tc.localExploration),
                        ResultsReducer.text(activity["location"]) ?? dest, hours,
                        ResultsReducer.text(activity["description"]) ?? "", price))
            }
            return slots
        }
    }

    fileprivate static func text(_ value: JSONValue?) -> String? {
        guard let string = value?.string, !string.isEmpty else { return nil }
        return string
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// `YYYY-MM-DD` (the first ten characters of an ISO date) at UTC midnight, like JS `Date.parse`.
    private static func parse(_ string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func format(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
