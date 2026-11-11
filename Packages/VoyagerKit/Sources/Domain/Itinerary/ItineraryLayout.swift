import Foundation
import VoyagerModel

/// Drag-and-drop itinerary editing: a layout overlay keyed by each activity's ORIGINAL slot key
/// (`"<day_number>-<time_of_day>"`). Edits, notes, plan picks and calendar UIDs stay attached to that key,
/// so moving an activity never re-keys anything. Layout shape:
/// `{ fingerprint, positions: { [originalKey]: "<day>-<tod>" | null } }` (`null` = removed; an absent key
/// stays where it was).
///
/// Line-by-line port of `frontend/src/utils/itineraryLayout.js` over `JSONValue`. A layout of `nil` or
/// `.null` is "no layout".
public enum ItineraryLayout {}

// MARK: - Shapes

extension ItineraryLayout {
    static func days(of itinerary: JSONValue?) -> [JSONValue] {
        itinerary?["days"].array ?? []
    }

    static func slots(of day: JSONValue) -> [JSONValue] {
        day["slots"].array ?? []
    }

    /// `{...base, ...extra}`.
    static func merged(_ base: JSONValue, _ extra: [String: JSONValue]) -> JSONValue {
        var object = base.object ?? [:]
        for (key, value) in extra { object[key] = value }
        return .object(object)
    }
}

// MARK: - Fingerprint and active layout

extension ItineraryLayout {
    /// FNV-1a (32-bit) over `"<day>|<time_of_day>|<activity>"` lines, base 36.
    public static func fingerprint(_ itinerary: JSONValue?) -> String {
        var lines: [String] = []
        for day in days(of: itinerary) {
            for slot in slots(of: day) {
                let dayNumber = JSCoerce.interpolate(day, "day_number")
                lines.append("\(dayNumber)|\(JSCoerce.interpolate(slot, "time_of_day"))|\(JSCoerce.interpolate(slot, "activity"))")
            }
        }
        return FNV1a.base36(lines.joined(separator: "\n"))
    }

    /// The layout when it belongs to this itinerary (same fingerprint), else `nil`.
    public static func activeLayout(_ itinerary: JSONValue?, _ layout: JSONValue?) -> JSONValue? {
        guard let layout, layout.object != nil else { return nil }
        guard layout["positions"].object != nil else { return nil }
        guard layout["fingerprint"] == .string(fingerprint(itinerary)) else { return nil }
        return layout
    }

    /// Keys of a day's slots, in order. The first slot with a given time keeps `"<day>-<tod>"`; later
    /// ones get `#2`, `#3`, ... suffixes.
    static func dayKeys(_ day: JSONValue) -> [String] {
        var counts: [String: Int] = [:]
        return slots(of: day).map { slot in
            let base = slotKey(day["day_number"], slot["time_of_day"])
            let count = (counts[base] ?? 0) + 1
            counts[base] = count
            return count == 1 ? base : "\(base)#\(count)"
        }
    }

    /// Movable: a standard time and the first slot of that time on its day (key exactly `"<day>-<tod>"`).
    static func isMovable(_ day: JSONValue, _ slot: JSONValue, _ key: String) -> Bool {
        guard let tod = slot["time_of_day"].string, times.contains(tod) else { return false }
        return key == slotKey(day["day_number"], slot["time_of_day"])
    }

    /// Sort rank of every slot of an ORIGINAL day, in slot order: a movable slot ranks at its time's
    /// index; any other slot ranks just after the movable slot before it (-0.5 when none).
    public static func slotRanks(_ day: JSONValue) -> [(key: String, rank: Double)] {
        var result: [(key: String, rank: Double)] = []
        var rank = -1.0
        let keys = dayKeys(day)
        for (index, slot) in slots(of: day).enumerated() {
            if isMovable(day, slot, keys[index]), let tod = slot["time_of_day"].string,
               let at = times.firstIndex(of: tod) {
                rank = Double(at)
                result.append((keys[index], rank))
            } else {
                result.append((keys[index], rank + 0.5))
            }
        }
        return result
    }

    /// `"Montserrat & Barcelona, Spain"` -> `{montserrat, barcelona}`.
    private static func placeNames(_ city: JSONValue) -> Set<String> {
        // `String(city || '')`: a falsy city is empty, anything else is stringified.
        let text = city.isTruthy ? JSCoerce.interpolate(city) : ""
        let first = text.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let parts = first.split(separator: /&|\/|\+|\band\b/.ignoresCase(), omittingEmptySubsequences: false)
        var names = Set<String>()
        for part in parts {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !name.isEmpty { names.insert(name) }
        }
        return names
    }

    /// Two days are compatible when their place-name sets share a name, or either day has no city.
    public static func citiesCompatible(_ first: JSONValue?, _ second: JSONValue?) -> Bool {
        let left = placeNames(first ?? .null)
        let right = placeNames(second ?? .null)
        if left.isEmpty || right.isEmpty { return true }
        return !left.isDisjoint(with: right)
    }
}

// MARK: - Model and resolution

extension ItineraryLayout {
    /// Index of the original itinerary: movable activities and every valid position. Positions exist
    /// only on days that have at least one standard-time slot.
    private struct Model {
        var positions: [String] = []
        var posDay: [String: JSONValue] = [:]
        var slotByKey: [String: JSONValue] = [:]
        var movable: [String] = []
    }

    private enum Place: Equatable {
        case at(String)
        case removed
    }

    /// Insertion-ordered key -> place map (a JS `Map`).
    private struct Resolved {
        var order: [String] = []
        var places: [String: Place] = [:]

        mutating func set(_ key: String, _ place: Place) {
            if places[key] == nil { order.append(key) }
            places[key] = place
        }

        func occupant(of position: String) -> String? {
            order.first { places[$0] == .at(position) }
        }
    }

    private static func buildModel(_ itinerary: JSONValue?) -> Model {
        var model = Model()
        for day in days(of: itinerary) {
            let standard = slots(of: day).contains { slot in
                guard let tod = slot["time_of_day"].string else { return false }
                return times.contains(tod)
            }
            guard standard else { continue }
            for tod in times {
                let position = slotKey(day["day_number"], .string(tod))
                model.positions.append(position)
                model.posDay[position] = day
            }
        }
        for day in days(of: itinerary) {
            let keys = dayKeys(day)
            for (index, slot) in slots(of: day).enumerated() where isMovable(day, slot, keys[index]) {
                model.slotByKey[keys[index]] = slot
                model.movable.append(keys[index])
            }
        }
        return model
    }

    /// Effective position of every movable key: a position, or removed.
    private static func resolve(_ model: Model, _ layout: JSONValue?) -> Resolved {
        var resolved = Resolved()
        var taken = Set<String>()
        let claims = layout?["positions"].object ?? [:]
        for key in model.movable {
            var desired = key
            if let want = claims[key] {
                if want.isNull {
                    resolved.set(key, .removed)
                    continue
                }
                if let target = want.string, let targetDay = model.posDay[target],
                   let ownDay = model.posDay[key], citiesCompatible(ownDay["city"], targetDay["city"]) {
                    desired = target
                }
            }
            if !taken.contains(desired) {
                taken.insert(desired)
                resolved.set(key, .at(desired))
            } else if !taken.contains(key) {
                taken.insert(key)
                resolved.set(key, .at(key))
            } else {
                resolved.set(key, .removed)
            }
        }
        return resolved
    }

    /// Sparse layout from a resolved map: only keys away from their original spot.
    private static func layoutFrom(_ itinerary: JSONValue?, _ resolved: Resolved) -> JSONValue {
        var positions: [String: JSONValue] = [:]
        for key in resolved.order {
            switch resolved.places[key] {
            case .at(let position)? where position != key: positions[key] = .string(position)
            case .removed?: positions[key] = .null
            default: break
            }
        }
        return .object(["fingerprint": .string(fingerprint(itinerary)), "positions": .object(positions)])
    }
}

// MARK: - Arrangement

extension ItineraryLayout {
    private static func slotCost(_ slot: JSONValue, _ edits: JSONValue) -> Double {
        var cost = JSONValue.null
        if let key = slot["key"].string { cost = edits[key]["cost"] }
        if cost.isNull { cost = slot["estimated_cost_usd"] }
        if case .number(let number) = cost, number.isFinite { return number }
        return 0
    }

    private static func withKeys(_ day: JSONValue) -> [JSONValue] {
        let keys = dayKeys(day)
        return slots(of: day).enumerated().map { merged($1, ["key": .string(keys[$0])]) }
    }

    private static func plainArrangement(_ itinerary: JSONValue?) -> JSONValue {
        let arranged = days(of: itinerary).map { merged($0, ["slots": .array(withKeys($0))]) }
        return merged(itinerary ?? .null, ["days": .array(arranged), "removed": .array([]), "changed": .bool(false)])
    }

    private static func daySlotCost(_ day: JSONValue, _ edits: JSONValue) -> Double {
        slots(of: day).reduce(0) { $0 + slotCost($1, edits) }
    }

    private static func arrangeDay(
        _ day: JSONValue, changed: Set<JSONValue>, placed: [String: String], model: Model, edits: JSONValue
    ) -> JSONValue {
        guard changed.contains(day["day_number"]) else {
            return merged(day, ["slots": .array(withKeys(day))])
        }
        // Odd-time and duplicate slots stay put: sorted just after the standard time that preceded
        // them in the original day (before everything if none).
        var entries: [(rank: Double, slot: JSONValue)] = []
        for (rank, tod) in times.enumerated() {
            guard let key = placed[slotKey(day["day_number"], .string(tod))] else { continue }
            let slot = merged(model.slotByKey[key] ?? .null, ["key": .string(key), "time_of_day": .string(tod)])
            entries.append((Double(rank), slot))
        }
        let keys = dayKeys(day)
        let ranks = slotRanks(day)
        for (index, slot) in slots(of: day).enumerated() where !isMovable(day, slot, keys[index]) {
            entries.append((ranks[index].rank, merged(slot, ["key": .string(keys[index])])))
        }
        // Stable: ties keep their order, like `Array.prototype.sort`.
        let sorted = entries.enumerated().sorted { lhs, rhs in
            lhs.element.rank != rhs.element.rank ? lhs.element.rank < rhs.element.rank : lhs.offset < rhs.offset
        }.map(\.element.slot)
        let cost = sorted.reduce(0.0) { $0 + slotCost($1, edits) }
        return merged(day, ["slots": .array(sorted), "daily_estimated_cost_usd": .number(cost)])
    }

    private static func totalCost(
        _ itinerary: JSONValue, _ originalDays: [JSONValue], _ arrangedDays: [JSONValue],
        _ changedDays: Set<JSONValue>, _ edits: JSONValue
    ) -> Double {
        if case .number(let base) = itinerary["total_estimated_cost_usd"], base.isFinite {
            var running = base
            for (index, original) in originalDays.enumerated() where changedDays.contains(original["day_number"]) {
                var before = daySlotCost(original, .object([:]))
                if case .number(let own) = original["daily_estimated_cost_usd"], own.isFinite { before = own }
                if case .number(let after) = arrangedDays[index]["daily_estimated_cost_usd"] { running += after - before }
            }
            return running
        }
        return arrangedDays.reduce(0.0) { sum, day in
            if case .number(let own) = day["daily_estimated_cost_usd"], own.isFinite { return sum + own }
            return sum + daySlotCost(day, edits)
        }
    }

    /// The itinerary with the layout applied: `days` rearranged (keys attached), `removed` slots, `changed`,
    /// and day / total costs recomputed (edited costs from `edits[key].cost`).
    public static func arrange(_ itinerary: JSONValue, layout: JSONValue?, edits: JSONValue = .object([:])) -> JSONValue {
        guard let active = activeLayout(itinerary, layout) else { return plainArrangement(itinerary) }
        let model = buildModel(itinerary)
        let resolved = resolve(model, active)

        var changedDays = Set<JSONValue>()
        var removed: [JSONValue] = []
        for key in resolved.order {
            guard let place = resolved.places[key], place != .at(key) else { continue }
            if let day = model.posDay[key] { changedDays.insert(day["day_number"]) }
            switch place {
            case .removed:
                let slot = merged(model.slotByKey[key] ?? .null, ["key": .string(key)])
                removed.append(.object(["key": .string(key), "slot": slot]))
            case .at(let position):
                if let day = model.posDay[position] { changedDays.insert(day["day_number"]) }
            }
        }
        if changedDays.isEmpty { return plainArrangement(itinerary) }

        var placed: [String: String] = [:]
        for key in resolved.order {
            if case .at(let position)? = resolved.places[key] { placed[position] = key }
        }

        let originalDays = days(of: itinerary)
        let arrangedDays = originalDays.map {
            arrangeDay($0, changed: changedDays, placed: placed, model: model, edits: edits)
        }
        let total = totalCost(itinerary, originalDays, arrangedDays, changedDays, edits)
        return merged(itinerary, [
            "days": .array(arrangedDays), "total_estimated_cost_usd": .number(total),
            "removed": .array(removed), "changed": .bool(true),
        ])
    }
}

// MARK: - Editing

extension ItineraryLayout {
    /// Every other position the slot can move to (cities must be compatible), with the activity it would
    /// swap with, if any: `{day_number, time_of_day, swapWith: {key, activity} | null}`.
    public static func moveTargets(_ itinerary: JSONValue, layout: JSONValue?, key: String) -> [JSONValue] {
        let model = buildModel(itinerary)
        let resolved = resolve(model, activeLayout(itinerary, layout))
        guard case .at(let from)? = resolved.places[key], let fromDay = model.posDay[from] else { return [] }
        var targets: [JSONValue] = []
        for position in model.positions where position != from {
            guard let day = model.posDay[position], citiesCompatible(fromDay["city"], day["city"]) else { continue }
            var swap = JSONValue.null
            if let occupant = resolved.occupant(of: position) {
                var entry: [String: JSONValue] = ["key": .string(occupant)]
                if let activity = model.slotByKey[occupant]?.object?["activity"] { entry["activity"] = activity }
                swap = .object(entry)
            }
            let prefix = JSCoerce.interpolate(day, "day_number").count + 1
            var target: [String: JSONValue] = [
                "time_of_day": .string(String(position.dropFirst(prefix))), "swapWith": swap,
            ]
            if let number = day.object?["day_number"] { target["day_number"] = number }
            targets.append(.object(target))
        }
        return targets
    }

    /// Move the slot to `day` / `timeOfDay` (swapping with its occupant). The layout comes back unchanged
    /// when that is not a valid target.
    public static func moveSlot(_ itinerary: JSONValue, layout: JSONValue?, key: String, day: Int, timeOfDay: String) -> JSONValue {
        let targets = moveTargets(itinerary, layout: layout, key: key)
        let target = targets.first { $0["day_number"] == .number(Double(day)) && $0["time_of_day"] == .string(timeOfDay) }
        guard let target else { return layout ?? .null }
        let model = buildModel(itinerary)
        var resolved = resolve(model, activeLayout(itinerary, layout))
        guard let from = resolved.places[key] else { return layout ?? .null }
        if let swapKey = target["swapWith"]["key"].string { resolved.set(swapKey, from) }
        resolved.set(key, .at(slotKey(day: day, timeOfDay: timeOfDay)))
        return layoutFrom(itinerary, resolved)
    }

    public static func removeSlot(_ itinerary: JSONValue, layout: JSONValue?, key: String) -> JSONValue {
        let model = buildModel(itinerary)
        var resolved = resolve(model, activeLayout(itinerary, layout))
        guard case .at(_)? = resolved.places[key] else { return layout ?? .null }
        resolved.set(key, .removed)
        return layoutFrom(itinerary, resolved)
    }

    /// Put a removed slot back at its original position, else the first free time that day.
    public static func restoreSlot(_ itinerary: JSONValue, layout: JSONValue?, key: String) -> JSONValue {
        guard let layout, !layout.isNull, activeLayout(itinerary, layout) != nil else { return layout ?? .null }
        let model = buildModel(itinerary)
        var resolved = resolve(model, layout)
        guard resolved.places[key] == .removed, let originalDay = model.posDay[key] else { return layout }
        let candidates = [key] + times.map { slotKey(originalDay["day_number"], .string($0)) }
        guard let free = candidates.first(where: { resolved.occupant(of: $0) == nil }) else { return layout }
        resolved.set(key, .at(free))
        return layoutFrom(itinerary, resolved)
    }

    /// How many activities are away from their original spot (moved or removed).
    public static func layoutChangeCount(_ itinerary: JSONValue, layout: JSONValue?) -> Int {
        guard let active = activeLayout(itinerary, layout) else { return 0 }
        let resolved = resolve(buildModel(itinerary), active)
        return resolved.order.filter { resolved.places[$0] != .at($0) }.count
    }

    /// Re-point picked itinerary entries (by `key`) at the arranged day / time they now sit in.
    public static func syncPlannedSlots(_ itinerarySlots: JSONValue?, _ arranged: JSONValue?) -> JSONValue {
        var whereIs: [String: (day: JSONValue, tod: JSONValue)] = [:]
        for day in arranged?["days"].array ?? [] {
            for slot in day["slots"].array ?? [] {
                if let key = slot["key"].string { whereIs[key] = (day["day_number"], slot["time_of_day"]) }
            }
        }
        let entries = itinerarySlots?.array ?? []
        return .array(entries.map { entry in
            guard let key = entry["key"].string, let at = whereIs[key] else { return entry }
            if at.day == entry["day_number"], at.tod == entry["time_of_day"] { return entry }
            return merged(entry, ["day_number": at.day, "time_of_day": at.tod])
        })
    }
}
