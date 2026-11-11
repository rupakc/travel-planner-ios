import Foundation
import VoyagerModel

/// iCalendar (.ics, RFC 5545) export of a plan: a port of `buildPlanIcs` in `frontend/src/utils/planExport.js`
/// that produces the same bytes (CRLF line ends, 75-octet folding, TEXT escaping, stable UIDs), golden-tested
/// against the web. Times are "floating" (no time zone): a 09:00 museum visit in Tokyo reads 09:00 in the
/// traveller's calendar wherever it is opened.
///
/// Itinerary days come from Task 9's `ItineraryLayout.arrange` and `Schedule.scheduleDays` (the same pipeline
/// the web's `planItineraryDays` uses).
public enum PlanICS {
    /// The few user-visible strings inside the file. Defaults are the web's English copy (`plan:ics.*`,
    /// `plan:print.*`); the plan feature passes localised ones.
    public struct Labels: Sendable {
        public var dayTheme: @Sendable (_ day: String, _ theme: String) -> String
        public var fromLinkQuote: @Sendable (String) -> String
        public var fromLink: String
        public var alsoFromLink: @Sendable (String) -> String
        public var estCost: @Sendable (String) -> String
        public var arrives: @Sendable (String) -> String
        public var booking: @Sendable (String) -> String
        public var price: @Sendable (String) -> String
        public var trip: String
        public var defaultName: String
        public var inspiredBy: @Sendable (String) -> String

        public static let english = Labels(
            dayTheme: { "Day \($0): \($1)" },
            fromLinkQuote: { "From your link: \u{201C}\($0)\u{201D}" },
            fromLink: "From your link",
            alsoFromLink: { "Also from your link: \($0)" },
            estCost: { "Est. cost: \($0)" },
            arrives: { "Arrives \($0) local time" },
            booking: { "Booking: \($0)" },
            price: { "Price: \($0)" },
            trip: "Trip",
            defaultName: "Trip plan",
            inspiredBy: { "Inspired by \($0)" }
        )
    }

    /// The `.ics` text for a plan. `itinerary` is the live itinerary when the plan comes straight from a search;
    /// saved plans carry their own snapshot in `selections.itinerary`. `planID` is the saved plan's id.
    public static func build(
        planName: String,
        searchData: JSONValue,
        selections: JSONValue,
        itinerary: JSONValue? = nil,
        planID: Int? = nil,
        now: Date = Date(),
        labels: Labels = .english
    ) -> String {
        let events: [Event] = flightEvents(selections, searchData, labels)
            + [hotelEvent(selections["hotel"], searchData, labels)].compactMap { $0 }
            + localEvents(selections["events"], labels)
            + itineraryEvents(planItineraryDays(selections: selections, itinerary: itinerary), selections, searchData, labels)

        let stamp = icsStamp(now)
        let base = uidBase(planID: planID, planName: planName, searchData: searchData)
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Voyager Travel Planner//Plan Export//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:\(escape(planName.isEmpty ? labels.defaultName : planName))",
        ]
        let source = searchData["import_source"]
        if source["title"].isTruthy || source["url"].isTruthy {
            let rawURL = source["url"].isTruthy ? ExportText.js(source["url"]) : ""
            let url = rawURL.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil ? rawURL : ""
            let title = source["title"].isTruthy ? ExportText.js(source["title"]) : nil
            lines.append("X-WR-CALDESC:\(escape(labels.inspiredBy(ExportText.joined([title, url], " \u{2014} "))))")
        }
        for event in events {
            let dateParam = event.allDay ? ";VALUE=DATE" : ""
            lines += [
                "BEGIN:VEVENT",
                // Stable per plan + item, so re-importing updates rather than duplicates.
                "UID:\(base)-\(event.id)@voyager-travel-planner",
                "DTSTAMP:\(stamp)",
                "DTSTART\(dateParam):\(event.start)",
            ]
            if let end = event.end { lines.append("DTEND\(dateParam):\(end)") }
            lines.append("SUMMARY:\(escape(event.summary.isEmpty ? labels.trip : event.summary))")
            if !event.location.isEmpty { lines.append("LOCATION:\(escape(event.location))") }
            if !event.description.isEmpty { lines.append("DESCRIPTION:\(escape(event.description))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// Escape a TEXT value (RFC 5545 section 3.3.11): control characters (tab is allowed) are dropped, then
    /// backslash, semicolon and comma are escaped and every line break becomes `\n`.
    public static func escape(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var pendingCR = false
        for scalar in text.unicodeScalars {
            let code = scalar.value
            if code <= 0x08 || code == 0x0B || code == 0x0C || (0x0E...0x1F).contains(code) || code == 0x7F { continue }
            if pendingCR {
                pendingCR = false
                out.append(contentsOf: "\\n".unicodeScalars)
                if code == 0x0A { continue }
            }
            switch code {
            case 0x5C: out.append(contentsOf: "\\\\".unicodeScalars)
            case 0x3B: out.append(contentsOf: "\\;".unicodeScalars)
            case 0x2C: out.append(contentsOf: "\\,".unicodeScalars)
            case 0x0A: out.append(contentsOf: "\\n".unicodeScalars)
            case 0x0D: pendingCR = true
            default: out.append(scalar)
            }
        }
        if pendingCR { out.append(contentsOf: "\\n".unicodeScalars) }
        return String(out)
    }

    /// Fold a content line to at most 75 octets per line (RFC 5545 section 3.1); continuation lines start with a
    /// space, which counts toward the 75. Folds between code points, never inside one.
    public static func fold(_ line: String) -> String {
        if line.utf8.count <= 75 { return line }
        var pieces: [String] = []
        var current = String.UnicodeScalarView()
        var bytes = 0
        for scalar in line.unicodeScalars {
            let size = String(scalar).utf8.count
            let limit = pieces.isEmpty ? 75 : 74
            if bytes + size > limit {
                pieces.append(String(current))
                current = String.UnicodeScalarView()
                bytes = 0
            }
            current.append(scalar)
            bytes += size
        }
        pieces.append(String(current))
        return pieces.joined(separator: "\r\n ")
    }

    /// A safe download file name for the plan, e.g. "tokyo-trip.ics".
    public static func fileName(planName: String?, ext: String) -> String {
        "\(slug(planName)).\(ext)"
    }

    /// The plan's day-by-day itinerary: the live one if given, else the snapshot saved with the plan, arranged by
    /// the user's layout and given estimated times; else the individually selected slots grouped by day (no times).
    public static func planItineraryDays(selections: JSONValue, itinerary: JSONValue?) -> [JSONValue] {
        func arranged(_ source: JSONValue) -> [JSONValue] {
            let edits = ExportText.or(selections["itinerary_edits"], .object([:]))
            let layout = selections["itinerary_layout"]
            let days = ItineraryLayout.arrange(source, layout: layout.isNull ? nil : layout, edits: edits)["days"]
            return Schedule.scheduleDays(days, edits: edits).array ?? []
        }
        if let itinerary, !(itinerary["days"].array ?? []).isEmpty { return arranged(itinerary) }
        if !(selections["itinerary"]["days"].array ?? []).isEmpty { return arranged(selections["itinerary"]) }

        struct Group { var day: [String: JSONValue]; var slots: [JSONValue] }
        var order: [JSONValue] = []
        var groups: [JSONValue: Group] = [:]
        for slot in selections["itinerary_slots"].array ?? [] {
            let number = slot["day_number"]
            if groups[number] == nil {
                order.append(number)
                groups[number] = Group(day: ["day_number": number, "date": slot["date"]], slots: [])
            }
            groups[number]?.slots.append(slot)
        }
        let rank = { (slot: JSONValue) in ["morning", "afternoon", "evening"].firstIndex(of: slot["time_of_day"].string ?? "") ?? -1 }
        return order
            .sorted { ($0.double ?? .nan) < ($1.double ?? .nan) }
            .compactMap { number -> JSONValue? in
                guard var group = groups[number] else { return nil }
                group.day["slots"] = .array(group.slots.enumerated().sorted {
                    let (left, right) = (rank($0.element), rank($1.element))
                    return left != right ? left < right : $0.offset < $1.offset
                }.map(\.element))
                return .object(group.day)
            }
    }

    // MARK: - Events

    struct Event {
        var id: String
        var summary: String
        var location = ""
        var description = ""
        var allDay = false
        var start: String
        var end: String?
    }

    private static let slotHours: [String: (start: Int, end: Int)] = [
        "morning": (9, 12), "afternoon": (13, 17), "evening": (18, 21),
    ]

    private static func itineraryEvents(
        _ days: [JSONValue], _ selections: JSONValue, _ searchData: JSONValue, _ labels: Labels
    ) -> [Event] {
        var events: [Event] = []
        for day in days {
            guard let date = dayDate(day, searchData) else { continue }
            for slot in day["slots"].array ?? [] {
                events.append(slotEvent(slot, day: day, date: date, selections: selections, labels))
            }
            if let extras = linkExtrasEvent(day, date: date, labels) { events.append(extras) }
        }
        return events
    }

    private static func slotEvent(
        _ slot: JSONValue, day: JSONValue, date: String, selections: JSONValue, _ labels: Labels
    ) -> Event {
        let key = !slot["key"].isNull
            ? ExportText.js(slot["key"])
            : "\(ExportText.js(day["day_number"]))-\(ExportText.js(slot["time_of_day"]))"
        let edit = ExportText.or(selections["itinerary_edits"][key], .object([:]))
        let note = selections["itinerary_notes"][key]
        let (start, end) = slotMinutes(slot)
        let cost = ExportText.coalesce(edit["cost"], slot["estimated_cost_usd"])
        var parts: [String?] = []
        if day["theme"].isTruthy {
            parts.append(labels.dayTheme(ExportText.js(day["day_number"]), ExportText.js(day["theme"])))
        }
        if slot["from_link"].isTruthy {
            parts.append(slot["link_quote"].isTruthy ? labels.fromLinkQuote(ExportText.js(slot["link_quote"])) : labels.fromLink)
        }
        parts.append(slot["notes"].isTruthy ? ExportText.js(slot["notes"]) : nil)
        parts.append(note.isTruthy ? ExportText.js(note) : nil)
        if ExportText.isPositive(cost) { parts.append(labels.estCost(ExportText.usdUpTo2(cost.double ?? 0))) }
        let summary = ExportText.or(edit["activity"], slot["activity"])
        let location = ExportText.coalesce(ExportText.coalesce(edit["location"], slot["location"]), day["city"])
        return Event(
            id: "slot-\(key)",
            summary: summary.isTruthy ? ExportText.js(summary) : "",
            location: location.isTruthy ? ExportText.js(location) : "",
            description: ExportText.joined(parts, "\n"),
            start: icsDateTime(date, start),
            end: icsDateTime(date, end)
        )
    }

    /// Start and end in minutes past midnight of the trip day (may pass 1440): the slot's scheduled clock times
    /// with their day offsets, else its time of day's standard hours or its duration.
    private static func slotMinutes(_ slot: JSONValue) -> (start: Int, end: Int) {
        if let scheduledStart = clockMinutes(slot["start_time"]), let scheduledEnd = clockMinutes(slot["end_time"]) {
            // Scheduled clock times wrap at midnight; the day offsets say which day.
            return (scheduledStart + dayOffset(slot["start_day_offset"]) * 1440,
                    scheduledEnd + dayOffset(slot["end_day_offset"]) * 1440)
        }
        let fallback = (start: 9, end: 12)
        let hours = slotHours[slot["time_of_day"].string ?? ""] ?? slotHours["morning"] ?? fallback
        let start = hours.start * 60
        let duration = slot["duration_hours"]
        return (start, ExportText.isPositive(duration) ? start + ExportText.round((duration.double ?? 0) * 60) : hours.end * 60)
    }

    private static func linkExtrasEvent(_ day: JSONValue, date: String, _ labels: Labels) -> Event? {
        let extras = day["link_extras"].array ?? []
        guard !extras.isEmpty else { return nil }
        let names = extras.map { ExportText.joinItem($0["name"]) }.joined(separator: ", ")
        let lines = extras.map { extra in
            ExportText.joined([extra["name"], extra["note"]].map { $0.isTruthy ? ExportText.js($0) : nil }, " \u{2014} ")
        }
        return Event(
            id: "extras-\(ExportText.js(day["day_number"]))",
            summary: labels.alsoFromLink(names),
            description: lines.joined(separator: "\n"),
            allDay: true,
            start: icsDate(date),
            end: icsDate(IsoDayMath.add(date, days: 1))
        )
    }

    private static func flightEvent(
        id: String, leg: JSONValue, date: JSONValue, fallbackFrom: JSONValue = .null, fallbackTo: JSONValue = .null,
        bookingURL: JSONValue, _ labels: Labels
    ) -> Event? {
        guard leg.isTruthy, date.isTruthy, let iso = date.string, IsoDayMath.isIsoDate(iso) else { return nil }
        let from = leg["origin"].isTruthy ? ExportText.js(leg["origin"]) : ExportText.shortPlace(fallbackFrom)
        let to = leg["destination"].isTruthy ? ExportText.js(leg["destination"]) : ExportText.shortPlace(fallbackTo)
        let truthyText = { (value: JSONValue) -> String? in value.isTruthy ? ExportText.js(value) : nil }
        let summary = ExportText.joined(
            ["\u{2708}", truthyText(leg["airline"]), truthyText(leg["flight_number"]),
             !from.isEmpty && !to.isEmpty ? "\(from) \u{2192} \(to)" : ""], " ")
        // Floating times follow the departure clock, so the arrival (in the destination's clock) is spelled out.
        let description = ExportText.joined([
            leg["arrival_time"].isTruthy ? labels.arrives(ExportText.js(leg["arrival_time"])) : nil,
            bookingURL.isTruthy ? labels.booking(ExportText.js(bookingURL)) : nil,
        ], "\n")
        guard let departs = parseTime(leg["departure_time"]) else {
            return Event(id: id, summary: summary, description: description, allDay: true,
                         start: icsDate(iso), end: icsDate(IsoDayMath.add(iso, days: 1)))
        }
        let duration = leg["duration_minutes"]
        return Event(
            id: id, summary: summary, description: description,
            start: icsDateTime(iso, departs),
            end: ExportText.isPositive(duration) ? icsDateTime(iso, departs + Int((duration.double ?? 0).rounded(.down))) : nil
        )
    }

    private static func flightEvents(_ selections: JSONValue, _ searchData: JSONValue, _ labels: Labels) -> [Event] {
        var events: [Event?] = []
        let flight = selections["flight"]
        if flight.isTruthy {
            let out = ExportText.or(flight["outbound"], flight)
            events.append(flightEvent(
                id: "flight-out", leg: out,
                date: ExportText.or(out["departure_date"], searchData["departure_date"]),
                bookingURL: flight["booking_url"], labels))
            if flight["return"].isTruthy {
                let back = flight["return"]
                events.append(flightEvent(
                    id: "flight-return", leg: back,
                    date: ExportText.or(back["departure_date"], searchData["return_date"]),
                    bookingURL: flight["booking_url"], labels))
            }
        }
        for (index, leg) in (selections["flights"].array ?? []).enumerated() {
            let out = ExportText.or(leg["outbound"], leg)
            let legIndex = ExportText.coalesce(leg["leg_index"], .number(Double(index)))
            events.append(flightEvent(
                id: "flight-leg-\(ExportText.js(legIndex))", leg: out,
                date: ExportText.or(out["departure_date"], leg["leg_date"]),
                fallbackFrom: leg["leg_from"], fallbackTo: leg["leg_to"],
                bookingURL: leg["booking_url"], labels))
        }
        return events.compactMap { $0 }
    }

    private static func hotelEvent(_ hotel: JSONValue, _ searchData: JSONValue, _ labels: Labels) -> Event? {
        guard hotel["name"].isTruthy, let checkIn = searchData["departure_date"].string, IsoDayMath.isIsoDate(checkIn) else {
            return nil
        }
        var checkOut = IsoDayMath.add(checkIn, days: 1)
        if let returnDate = searchData["return_date"].string, IsoDayMath.isIsoDate(returnDate), returnDate > checkIn {
            checkOut = returnDate
        }
        return Event(
            id: "hotel",
            summary: "\u{1F3E8} \(ExportText.js(hotel["name"]))",
            location: hotel["location"].isTruthy ? ExportText.js(hotel["location"]) : "",
            description: hotel["booking_url"].isTruthy ? labels.booking(ExportText.js(hotel["booking_url"])) : "",
            allDay: true,
            start: icsDate(checkIn),
            end: icsDate(checkOut)
        )
    }

    private static func localEvents(_ events: JSONValue, _ labels: Labels) -> [Event] {
        (events.array ?? []).compactMap { event in
            guard event["name"].isTruthy, let start = event["start_date"].string, IsoDayMath.isIsoDate(start) else { return nil }
            var last = start
            if let endDate = event["end_date"].string, IsoDayMath.isIsoDate(endDate), endDate >= start { last = endDate }
            let name = ExportText.js(event["name"])
            return Event(
                id: "event-\(fingerprint("\(name)|\(start)"))",
                summary: "\u{1F389} \(name)",
                location: event["location"].isTruthy ? ExportText.js(event["location"]) : "",
                description: ExportText.joined([
                    event["description"].isTruthy ? ExportText.js(event["description"]) : nil,
                    event["price"].isTruthy ? labels.price(ExportText.js(event["price"])) : nil,
                ], "\n"),
                allDay: true,
                start: icsDate(start),
                // All-day DTEND is exclusive: the day after the last day.
                end: icsDate(IsoDayMath.add(last, days: 1))
            )
        }
    }

    // MARK: - Helpers

    private static func dayDate(_ day: JSONValue, _ searchData: JSONValue) -> String? {
        if let date = day["date"].string, IsoDayMath.isIsoDate(date) { return date }
        if let departure = searchData["departure_date"].string, IsoDayMath.isIsoDate(departure),
           let number = day["day_number"].double, number >= 1 {
            return IsoDayMath.add(departure, days: Int(number.rounded(.down)) - 1)
        }
        return nil
    }

    /// "HH:MM" (exactly two digits each) to minutes past midnight.
    private static func clockMinutes(_ value: JSONValue) -> Int? {
        guard let text = value.string, let match = text.wholeMatch(of: /(\d{2}):(\d{2})/),
              let hour = Int(match.1), let minute = Int(match.2) else { return nil }
        return hour * 60 + minute
    }

    /// "11:55", "9:05", "11:55 PM" to minutes past midnight, or `nil`.
    private static func parseTime(_ value: JSONValue) -> Int? {
        guard let text = value.string, let match = text.prefixMatch(of: /\s*(\d{1,2}):(\d{2})\s*([aApP][mM])?/),
              var hour = Int(match.1), let minute = Int(match.2) else { return nil }
        let meridiem = match.3.map { $0.lowercased() }
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        if hour > 23 || minute > 59 { return nil }
        return hour * 60 + minute
    }

    /// A positive whole day offset, else 0.
    private static func dayOffset(_ value: JSONValue) -> Int {
        guard let offset = value.int, case .number = value, offset > 0 else { return 0 }
        return offset
    }

    private static func icsDate(_ iso: String) -> String { iso.replacingOccurrences(of: "-", with: "") }

    /// Floating local date-time: minutes past midnight of `iso`, which may roll over days.
    private static func icsDateTime(_ iso: String, _ minutes: Int) -> String {
        let dayShift = Int((Double(minutes) / 1440).rounded(.down))
        let rest = minutes - dayShift * 1440
        return "\(icsDate(IsoDayMath.add(iso, days: dayShift)))T\(String(format: "%02d%02d", rest / 60, rest % 60))00"
    }

    private static func icsStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// FNV-1a over code points, base 36: a short, stable fingerprint for event ids (not for security).
    private static func fingerprint(_ text: String) -> String {
        var hash: UInt32 = 0x811c_9dc5
        for scalar in text.unicodeScalars {
            hash ^= scalar.value
            hash = hash &* 0x0100_0193
        }
        return String(hash, radix: 36)
    }

    private static func slug(_ name: String?) -> String {
        let lowered = (name.flatMap { $0.isEmpty ? nil : $0 } ?? "trip").lowercased()
        let dashed = lowered.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        let trimmed = dashed.replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
        return trimmed.isEmpty ? "trip" : trimmed
    }

    /// Event ids must differ between plans (calendar apps merge events that share a UID) yet survive a rename:
    /// a saved plan's id is ideal; an unsaved plan falls back to its route, dates and name.
    private static func uidBase(planID: Int?, planName: String, searchData: JSONValue) -> String {
        if let planID { return "plan-\(planID)" }
        let trip = ["origin", "destination", "departure_date", "return_date"].map { ExportText.joinItem(searchData[$0]) } + [planName]
        return "trip-\(slug(planName))-\(fingerprint(trip.joined(separator: "|")))"
    }
}
