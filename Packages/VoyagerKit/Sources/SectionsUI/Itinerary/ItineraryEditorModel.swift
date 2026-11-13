import Domain
import Observation
import SwiftUI
import VoyagerModel

/// What the host (Results, Chat, Plan) gives the itinerary views: the raw itinerary, the My Plan selections
/// (layout, edits, notes, picked slots) and the stress-test call. Absent (Share, previews): the views keep
/// their edits in memory only.
public struct ItineraryHost: Sendable {
    public var itinerary: @MainActor @Sendable () -> JSONValue?
    public var selections: @MainActor @Sendable () -> JSONValue
    public var setSelections: @MainActor @Sendable (JSONValue) -> Void
    /// Sends the edited itinerary (`ItineraryEditorModel.recheckPayload`) to `repos.agents.stressTest`.
    public var recheck: (@MainActor @Sendable (JSONValue) async throws -> JSONValue)?
    public var editable: Bool

    public init(
        itinerary: @escaping @MainActor @Sendable () -> JSONValue?,
        selections: @escaping @MainActor @Sendable () -> JSONValue,
        setSelections: @escaping @MainActor @Sendable (JSONValue) -> Void,
        recheck: (@MainActor @Sendable (JSONValue) async throws -> JSONValue)? = nil,
        editable: Bool = true
    ) {
        self.itinerary = itinerary
        self.selections = selections
        self.setSelections = setSelections
        self.recheck = recheck
        self.editable = editable
    }
}

private struct ItineraryHostKey: EnvironmentKey {
    static var defaultValue: ItineraryHost? { nil }
}

extension EnvironmentValues {
    public var itineraryHost: ItineraryHost? {
        get { self[ItineraryHostKey.self] }
        set { self[ItineraryHostKey.self] = newValue }
    }
}

/// The itinerary as the user sees it, and every edit on it. Layout, edits, notes and picks live in the
/// selections value (so they round-trip to the plans API); times are derived, never stored, except that
/// picked slots keep the times they had when picked.
@MainActor @Observable
public final class ItineraryEditorModel {
    public private(set) var itinerary: JSONValue
    public private(set) var selections: JSONValue
    public private(set) var arranged: JSONValue = .null
    public private(set) var scheduledDays: [JSONValue] = []
    public private(set) var removed: [JSONValue] = []
    public private(set) var changeCount = 0
    public var editable: Bool
    /// Earlier layouts, for Undo (`null` = no layout).
    private var history: [JSONValue] = []
    @ObservationIgnored private var persist: (@MainActor @Sendable (JSONValue) -> Void)?

    public init(
        itinerary: JSONValue, selections: JSONValue = Selections.empty, editable: Bool = true,
        persist: (@MainActor @Sendable (JSONValue) -> Void)? = nil
    ) {
        self.itinerary = itinerary
        self.selections = selections.object == nil ? Selections.empty : selections
        self.editable = editable
        self.persist = persist
        refresh()
    }

    // MARK: Host sync

    public func attach(_ host: ItineraryHost?) {
        guard let host else { return }
        editable = host.editable
        persist = host.setSelections
        adopt(selections: host.selections())
        refresh()
    }

    public func update(itinerary new: JSONValue) {
        guard new != itinerary else { return }
        itinerary = new
        history = []
        refresh()
    }

    /// Selections changed elsewhere (plan loaded, picked from another section).
    public func adopt(selections new: JSONValue) {
        guard new.object != nil, new != selections else { return }
        selections = new
        refresh()
    }

    // MARK: Derived

    public var layout: JSONValue { selections["itinerary_layout"] }
    public var edits: JSONValue { selections["itinerary_edits"].object == nil ? .object([:]) : selections["itinerary_edits"] }
    public var notes: JSONValue { selections["itinerary_notes"] }
    public var canUndo: Bool { !history.isEmpty }
    public var hasDays: Bool { !(itinerary["days"].array ?? []).isEmpty }

    private func refresh() {
        // A stale layout (another itinerary's fingerprint) is ignored by `arrange` and `layoutChangeCount`.
        let layoutValue: JSONValue? = layout.isNull ? nil : layout
        arranged = ItineraryLayout.arrange(itinerary, layout: layoutValue, edits: edits)
        scheduledDays = Schedule.scheduleDays(arranged["days"], edits: edits).array ?? []
        removed = arranged["removed"].array ?? []
        changeCount = ItineraryLayout.layoutChangeCount(itinerary, layout: layoutValue)
    }

    public func targets(for key: String) -> [JSONValue] {
        guard editable else { return [] }
        return ItineraryLayout.moveTargets(itinerary, layout: layout.isNull ? nil : layout, key: key)
    }

    public func activityName(key: String, fallback: String?) -> String {
        if let edited = edits[key]["activity"].string, !edited.isEmpty { return edited }
        return fallback ?? ""
    }

    public func isPicked(key: String) -> Bool {
        (selections["itinerary_slots"].array ?? []).contains { $0["key"].string == key }
    }

    // MARK: Edits

    private func setSelections(_ field: String, _ value: JSONValue) {
        var object = selections.object ?? [:]
        object[field] = value
        selections = .object(object)
    }

    private func commit() {
        // Picked slots follow the arrangement and keep their scheduled times.
        let arrangedNow = arranged
        var slots = ItineraryLayout.syncPlannedSlots(selections["itinerary_slots"], arrangedNow)
        slots = Schedule.syncPlannedSlotTimes(slots, .array(scheduledDays))
        if !(slots.array ?? []).isEmpty { setSelections("itinerary_slots", slots) }
        persist?(selections)
    }

    private func applyLayout(_ new: JSONValue) {
        guard new != layout else { return }
        history.append(layout)
        setSelections("itinerary_layout", new)
        refresh()
        commit()
    }

    private func current() -> JSONValue? { layout.isNull ? nil : layout }

    /// Moves the slot to a valid target (swapping with its occupant). Anything else changes nothing.
    @discardableResult
    public func move(key: String, day: Int, timeOfDay: String) -> Bool {
        guard editable else { return false }
        let before = layout
        applyLayout(ItineraryLayout.moveSlot(itinerary, layout: current(), key: key, day: day, timeOfDay: timeOfDay))
        return layout != before
    }

    @discardableResult
    public func remove(key: String) -> Bool {
        guard editable else { return false }
        let before = layout
        applyLayout(ItineraryLayout.removeSlot(itinerary, layout: current(), key: key))
        return layout != before
    }

    /// False when the day has no free time left.
    @discardableResult
    public func restore(key: String) -> Bool {
        guard editable else { return false }
        let before = layout
        applyLayout(ItineraryLayout.restoreSlot(itinerary, layout: current(), key: key))
        return layout != before
    }

    public func undo() {
        guard editable, let previous = history.popLast() else { return }
        setSelections("itinerary_layout", previous)
        refresh()
        commit()
    }

    public func reset() {
        guard editable, !layout.isNull else { return }
        history = []
        setSelections("itinerary_layout", .null)
        refresh()
        commit()
    }

    /// `field` is `activity`, `location` or `cost`; an empty text clears it (`cost` is a number or `null`).
    public func setEdit(key: String, field: String, value: JSONValue) {
        guard editable else { return }
        var all = edits.object ?? [:]
        var entry = all[key].object ?? [:]
        entry[field] = value
        all[key] = .object(entry)
        setSelections("itinerary_edits", .object(all))
        refresh()
        commit()
    }

    public func setNote(key: String, text: String) {
        guard editable else { return }
        var all = notes.object ?? [:]
        all[key] = .string(text)
        setSelections("itinerary_notes", .object(all))
        persist?(selections)
    }

    /// Adds or removes the slot in `itinerary_slots`; an added slot carries its scheduled times.
    public func togglePick(_ slot: JSONValue, dayNumber: JSONValue) {
        guard let key = slot["key"].string else { return }
        let edit = edits[key]
        var item: [String: JSONValue] = [
            "key": .string(key), "day_number": dayNumber, "time_of_day": slot["time_of_day"],
            "activity": .string(activityName(key: key, fallback: slot["activity"].string)),
            "location": edit["location"].isNull ? slot["location"] : edit["location"],
            "estimated_cost_usd": edit["cost"].isNull ? slot["estimated_cost_usd"] : edit["cost"],
        ]
        for (name, value) in Schedule.pickedTimes(slot).object ?? [:] { item[name] = value }
        setSelections("itinerary_slots", Selections.toggle(selections, field: "itinerary_slots", item: .object(item))["itinerary_slots"])
        persist?(selections)
    }

    // MARK: Stress test

    /// The itinerary as the user now sees it (the web `editedItinerary`): arranged, removed slots left out,
    /// edits applied, estimated times and travel added, each day listed in timed order, no `key`.
    public func editedItinerary() -> JSONValue {
        var object = arranged.object ?? [:]
        for name in ["removed", "changed", "verification"] { object[name] = nil }
        let days: [JSONValue] = scheduledDays.map { day in
            var dayObject = day.object ?? [:]
            let slots = day["slots"].array ?? []
            let ordered = Schedule.scheduleOrder(day).compactMap { slots.indices.contains($0) ? slots[$0] : nil }
            dayObject["slots"] = .array(ordered.map(editedSlot))
            return .object(dayObject)
        }
        object["days"] = .array(days)
        return .object(object)
    }

    private func editedSlot(_ slot: JSONValue) -> JSONValue {
        var object = slot.object ?? [:]
        let edit = edits[slot["key"].string ?? ""]
        object["key"] = nil
        // The original description no longer matches a renamed activity.
        object["notes"] = nil
        if !edit["activity"].isTruthy, !slot["notes"].isNull { object["notes"] = slot["notes"] }
        if edit["activity"].isTruthy { object["activity"] = edit["activity"] }
        if !edit["location"].isNull { object["location"] = edit["location"] }
        if !edit["cost"].isNull { object["estimated_cost_usd"] = edit["cost"] }
        return .object(object)
    }

    public func recheckPayload() -> JSONValue { editedItinerary() }

    /// Identifies the edited itinerary a re-check ran against (layout + edits).
    public func recheckFingerprint() -> String {
        (try? JSONValue.array(editedItinerary()["days"].array ?? []).jsonString()) ?? ""
    }
}
