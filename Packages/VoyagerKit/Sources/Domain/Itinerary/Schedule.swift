import Foundation
import VoyagerModel

/// Estimated clock times for an arranged itinerary (see `ItineraryLayout.arrange`). Re-run after every edit:
/// times are derived from each slot's position, its own duration and the distance from the stop before it,
/// so they are never stored. Times are local wall-clock `"HH:MM"` strings with no time zone.
///
/// Line-by-line port of `frontend/src/utils/schedule.js` over `JSONValue`.
public enum Schedule {
    // Minutes past midnight each standard time starts at, at the earliest.
    private static let anchors: [String: Int] = ["morning": 9 * 60, "afternoon": 13 * 60 + 30, "evening": 18 * 60 + 30]
    private static let defaultMinutes: [String: Int] = ["morning": 180, "afternoon": 180, "evening": 150]
    // Duplicate and non-standard slots (e.g. "late night") have no default of their own.
    private static let otherDefaultMinutes = 120
    private static let minHours = 0.25
    private static let maxHours = 12.0

    private static let detour = 1.3 // street distance vs. straight line
    private static let walkMaxKm = 1.5
    private static let walkKmh = 4.5
    private static let transitKmh = 20.0
    private static let transitOverheadMinutes = 10.0 // getting to the stop, waiting
    private static let unknownTravelMinutes = 20 // buffer when either stop has no coordinates

    private static let lateMinutes = 45
    private static let dayEnd = 23 * 60

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

    private static func clock(_ minutes: Int) -> String {
        "\(pad(Int((Double(minutes) / 60).rounded(.down)) % 24)):\(pad(minutes % 60))"
    }

    private static func roundUpTo5(_ minutes: Double) -> Int {
        Int(max(5, (minutes / 5).rounded(.up) * 5))
    }

    /// Great-circle distance in km (`haversineKm` in `utils/geo.js`).
    static func haversineKm(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let radius = 6371.0
        let dLat = (lat2 - lat1) * Double.pi / 180
        let dLng = (lng2 - lng1) * Double.pi / 180
        let sinLat = sin(dLat / 2)
        let sinLng = sin(dLng / 2)
        let chord = sinLat * sinLat + cos(lat1 * Double.pi / 180) * cos(lat2 * Double.pi / 180) * sinLng * sinLng
        return radius * 2 * atan2(chord.squareRoot(), (1 - chord).squareRoot())
    }

    private static func finiteNumber(_ value: JSONValue) -> Double? {
        if case .number(let number) = value, number.isFinite { return number }
        return nil
    }

    private static func coords(_ slot: JSONValue) -> (lat: Double, lng: Double)? {
        guard let lat = finiteNumber(slot["lat"]), let lng = finiteNumber(slot["lng"]) else { return nil }
        if abs(lat) > 90 || abs(lng) > 180 { return nil }
        return (lat, lng)
    }

    private static func durationMinutes(_ slot: JSONValue) -> Int {
        if let hours = finiteNumber(slot["duration_hours"]), hours >= minHours, hours <= maxHours {
            return Int((hours * 60).rounded(.toNearestOrAwayFromZero))
        }
        let tod = slot["time_of_day"].string
        return tod.flatMap { defaultMinutes[$0] } ?? otherDefaultMinutes
    }

    private struct Transit {
        let minutes: Int
        let mode: String
        let km: Double
    }

    /// Travel from `prev` to `slot`, or `nil` when either lacks coordinates.
    private static func transitBetween(_ prev: JSONValue, _ slot: JSONValue) -> Transit? {
        guard let from = coords(prev), let to = coords(slot) else { return nil }
        let km = haversineKm(from.lat, from.lng, to.lat, to.lng) * detour
        let walk = km <= walkMaxKm
        let minutes = walk ? (km / walkKmh) * 60 : (km / transitKmh) * 60 + transitOverheadMinutes
        return Transit(minutes: roundUpTo5(minutes), mode: walk ? "walk" : "transit", km: (km * 10).rounded(.toNearestOrAwayFromZero) / 10)
    }

    private static func scheduleDay(_ day: JSONValue, _ edits: JSONValue) -> JSONValue {
        let slots = day["slots"].array ?? []
        let standard = slots.contains { slot in
            guard let tod = slot["time_of_day"].string else { return false }
            return ItineraryLayout.times.contains(tod)
        }
        guard standard else { return day }

        // A whole rank is the first slot of a standard time and starts no earlier than that time's anchor;
        // a fractional one (duplicate or non-standard time) simply follows the stop before it.
        let ranks = ItineraryLayout.slotRanks(day).map(\.rank)
        let order = scheduleOrder(day)

        var out = slots
        var warnings: [JSONValue] = []
        var prev: (slot: JSONValue, end: Int)?
        for index in order {
            let slot = slots[index]
            var anchor: Int?
            if ranks[index] == ranks[index].rounded(), ranks[index] >= 0, Int(ranks[index]) < ItineraryLayout.times.count {
                anchor = anchors[ItineraryLayout.times[Int(ranks[index])]]
            }
            if anchor == nil, prev == nil { continue } // nothing to follow: left untimed

            let transit = prev.flatMap { transitBetween($0.slot, slot) }
            let earliest = prev.map { $0.end + (transit?.minutes ?? unknownTravelMinutes) } ?? 0
            let start = max(anchor ?? 0, earliest)
            let end = start + durationMinutes(slot)
            var transitValue = JSONValue.null
            if let transit {
                transitValue = .object([
                    "minutes": .number(Double(transit.minutes)), "mode": .string(transit.mode), "km": .number(transit.km),
                ])
            }
            out[index] = ItineraryLayout.merged(slot, [
                "start_time": .string(clock(start)),
                "end_time": .string(clock(end)),
                // whole days past the trip day the clock time falls on (past midnight)
                "start_day_offset": .number(Double(start / 1440)),
                "end_day_offset": .number(Double(end / 1440)),
                "transit_from_prev": transitValue,
            ])

            if let anchor, start - anchor > lateMinutes {
                var name = "An activity"
                if let key = slot["key"].string, edits[key]["activity"].isTruthy {
                    name = JSCoerce.interpolate(edits[key]["activity"])
                } else if slot["activity"].isTruthy {
                    name = JSCoerce.interpolate(slot["activity"])
                }
                warnings.append(.string("\(name) starts at \(clock(start)) — later than planned"))
            }
            prev = (slot, end)
        }
        if let prev, prev.end > dayEnd {
            warnings.append(.string("Day \(JSCoerce.interpolate(day, "day_number")) runs past 23:00"))
        }
        return ItineraryLayout.merged(day, ["slots": .array(out), "schedule_warnings": .array(warnings)])
    }

    /// Indexes of a day's slots in the order `scheduleDays` times them (morning, afternoon, evening, by
    /// slot rank; ties keep their listed order).
    public static func scheduleOrder(_ day: JSONValue) -> [Int] {
        let ranks = ItineraryLayout.slotRanks(day).map(\.rank)
        return ranks.indices.sorted { ranks[$0] != ranks[$1] ? ranks[$0] < ranks[$1] : $0 < $1 }
    }

    /// True when a day's slots are listed in the order `scheduleDays` times them, so each slot's
    /// `transit_from_prev` is from a stop listed above it.
    public static func listedInScheduleOrder(_ day: JSONValue) -> Bool {
        let ranks = ItineraryLayout.slotRanks(day).map(\.rank)
        return ranks.indices.allSatisfy { $0 == 0 || ranks[$0 - 1] <= ranks[$0] }
    }

    /// Add estimated `start_time`, `end_time` (with `start_day_offset` / `end_day_offset`: whole days past
    /// the trip day) and `transit_from_prev` to every slot of arranged days, and `schedule_warnings` to
    /// every day. `edits` (by slot key) only rename activities in warnings; durations and coordinates
    /// always come from the slot itself. Days with no standard-time slot come back as they are.
    public static func scheduleDays(_ days: JSONValue, edits: JSONValue = .object([:])) -> JSONValue {
        .array((days.array ?? []).map { scheduleDay($0, edits) })
    }

    /// `"09:00–12:00"` for a timed slot, else `nil` (the web returns `""`).
    public static func timeRange(_ slot: JSONValue?) -> String? {
        guard let slot, slot["start_time"].isTruthy, slot["end_time"].isTruthy else { return nil }
        return "\(JSCoerce.interpolate(slot["start_time"]))–\(JSCoerce.interpolate(slot["end_time"]))"
    }

    /// Templates for `transitLabel` (`itinerary:transit.*`), supplied by the caller from its localised catalogue.
    /// `english` is for tests. `{{minutes}}` and `{{km}}` are replaced.
    public struct TransitStrings: Sendable, Equatable {
        public var walk: String
        public var walkKm: String
        public var transit: String

        public init(walk: String, walkKm: String, transit: String) {
            self.walk = walk
            self.walkKm = walkKm
            self.transit = transit
        }

        public static let english = TransitStrings(
            walk: "{{minutes}} min walk",
            walkKm: "{{minutes}} min walk · {{km}} km",
            transit: "~{{minutes}} min by transit"
        )

        func render(_ template: String, minutes: JSONValue, km: JSONValue? = nil) -> String {
            var text = template.replacingOccurrences(of: "{{minutes}}", with: JSCoerce.interpolate(minutes))
            if let km { text = text.replacingOccurrences(of: "{{km}}", with: JSCoerce.interpolate(km)) }
            return text
        }
    }

    /// `"🚶 12 min walk · 0.9 km"` (`"🚶 5 min walk"` under 100 m) / `"🚇 ~25 min by transit"`, or `nil` when
    /// travel is unknown (the web returns `""`).
    public static func transitLabel(_ transit: JSONValue?, strings: TransitStrings) -> String? {
        guard let transit, transit.isTruthy else { return nil }
        if transit["mode"] != .string("walk") {
            return "🚇 \(strings.render(strings.transit, minutes: transit["minutes"]))"
        }
        // km is rounded to 0.1, so anything shorter reads "0 km": leave it out
        if let km = finiteNumber(transit["km"]), km >= 0.1 {
            return "🚶 \(strings.render(strings.walkKm, minutes: transit["minutes"], km: transit["km"]))"
        }
        return "🚶 \(strings.render(strings.walk, minutes: transit["minutes"]))"
    }

    private static let pickedFields = ["start_time", "end_time", "start_day_offset", "end_day_offset", "duration_hours"]

    /// The timing of a scheduled slot, to store with a picked itinerary entry; `{}` when it is untimed.
    public static func pickedTimes(_ slot: JSONValue?) -> JSONValue {
        guard let slot, slot["start_time"].isTruthy, slot["end_time"].isTruthy else { return .object([:]) }
        var out: [String: JSONValue] = [:]
        for field in pickedFields {
            if let value = slot.object?[field] { out[field] = value }
        }
        return .object(out)
    }

    /// Refresh the stored times of picked itinerary entries (by key) from scheduled days. Entries with no
    /// timed counterpart are kept; the input comes back as it was when nothing changed.
    public static func syncPlannedSlotTimes(_ itinerarySlots: JSONValue?, _ scheduledDays: JSONValue?) -> JSONValue {
        var timed: [String: [String: JSONValue]] = [:]
        for day in scheduledDays?.array ?? [] {
            for slot in day["slots"].array ?? [] {
                guard let times = pickedTimes(slot).object, times["start_time"]?.isTruthy == true,
                      let key = slot["key"].string else { continue }
                timed[key] = times
            }
        }
        var changed = false
        let out: [JSONValue] = (itinerarySlots?.array ?? []).map { entry in
            guard let key = entry["key"].string, let times = timed[key] else { return entry }
            if times.allSatisfy({ entry.object?[$0.key] == $0.value }) { return entry }
            changed = true
            return ItineraryLayout.merged(entry, times)
        }
        return changed ? .array(out) : (itinerarySlots ?? .null)
    }

    /// `"Day 2 · Afternoon · 13:30–16:00"` for a picked itinerary entry; the times are left out when it has none.
    public static func slotWhen(_ slot: JSONValue?) -> String {
        var parts = ["Day \(slot.map { JSCoerce.interpolate($0, "day_number") } ?? "undefined")"]
        if let tod = slot?["time_of_day"], tod.isTruthy {
            let text = JSCoerce.interpolate(tod)
            parts.append(text.prefix(1).uppercased() + text.dropFirst())
        }
        if let range = timeRange(slot) { parts.append(range) }
        return parts.joined(separator: " · ")
    }
}
