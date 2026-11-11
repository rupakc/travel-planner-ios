import Foundation
import VoyagerModel

/// My Plan selections (`planHelpers.js` + the toggle rules of `ResultsPage.handleSelect`). A selections
/// value is a `JSONValue` object so it round-trips to the plans API unchanged.
public enum Selections {
    /// `EMPTY_SELECTIONS` of `planHelpers.js`.
    public static let empty: JSONValue = [
        "flight": nil,
        "flights": [],
        "hotel": nil,
        "activities": [],
        "places_to_see": [],
        "walking_tours": [],
        "sim": nil,
        "tips": [],
        "getting_around": [],
        "events": [],
        "itinerary_notes": [:],
        "itinerary_edits": [:],
        "itinerary_slots": [],
        "itinerary_layout": nil,
        "packing_list": nil,
    ]

    /// Fields that hold a list, and the key each list dedupes by.
    static let listKeys: [String: String] = [
        "activities": "name", "places_to_see": "name", "events": "name", "getting_around": "name",
        "tips": "title", "walking_tours": "url", "itinerary_slots": "key",
    ]

    /// Toggle `item` in `field`: lists add or remove it (deduped by `name`, `title` for tips, `url` for walking
    /// tours, `key` for itinerary slots); `flights` keeps one fare per `leg_index` (picking another fare on the
    /// leg replaces it, picking the same one deselects it); any other field is set to `item`.
    public static func toggle(_ selections: JSONValue, field: String, item: JSONValue) -> JSONValue {
        if let idKey = listKeys[field] {
            let list = selections[field].array ?? []
            let already = list.contains { $0[idKey] == item[idKey] }
            let next = already ? list.filter { $0[idKey] != item[idKey] } : list + [item]
            return PlanJS.set(selections, field, .array(next))
        }
        if field == "flights" {
            let list = selections["flights"].array ?? []
            let same = list.contains { sameFlight($0, item) }
            let rest = list.filter { $0["leg_index"] != item["leg_index"] }
            let next = same ? rest : PlanJS.sortBy(rest + [item], [{ lhs, rhs in
                (lhs["leg_index"].double ?? 0) - (rhs["leg_index"].double ?? 0)
            }])
            return PlanJS.set(selections, "flights", .array(next))
        }
        return PlanJS.set(selections, field, item)
    }

    /// Whether `item` is selected in `field` (lists by their dedupe key, flights by `sameFlight`, `hotel` by
    /// `name`, `sim` by provider + plan name, `flight` by `sameFlight`, `packing_list` when present).
    public static func contains(_ selections: JSONValue, field: String, item: JSONValue) -> Bool {
        if let idKey = listKeys[field] {
            return (selections[field].array ?? []).contains { $0[idKey] == item[idKey] }
        }
        switch field {
        case "flights": return (selections["flights"].array ?? []).contains { sameFlight($0, item) }
        case "flight": return sameFlight(selections["flight"], item)
        case "hotel":
            let current = selections["hotel"]
            return current.isTruthy && current["name"] == item["name"]
        case "sim":
            let current = selections["sim"]
            return current.isTruthy && current["provider"] == item["provider"] && current["plan_name"] == item["plan_name"]
        default: return selections[field].isTruthy
        }
    }

    /// `countSelections`.
    public static func count(_ selections: JSONValue) -> Int {
        func one(_ key: String) -> Int { selections[key].isTruthy ? 1 : 0 }
        func many(_ key: String) -> Int { selections[key].array?.count ?? 0 }
        return one("flight") + many("flights") + one("hotel") + many("activities") + many("places_to_see")
            + many("walking_tours") + one("sim") + many("getting_around") + many("tips") + many("events")
            + many("itinerary_slots") + one("packing_list")
    }

    /// Identity of per-leg flight selections (`sameFlight`): leg, price, airline and flight number.
    public static func sameFlight(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        guard lhs.isTruthy, rhs.isTruthy else { return false }
        func airline(_ fare: JSONValue) -> JSONValue { PlanJS.coalesce(fare["outbound"]["airline"], fare["airline"]) }
        func number(_ fare: JSONValue) -> JSONValue { PlanJS.coalesce(fare["outbound"]["flight_number"], fare["flight_number"]) }
        return lhs["leg_index"] == rhs["leg_index"] && lhs["price_usd"] == rhs["price_usd"]
            && airline(lhs) == airline(rhs) && number(lhs) == number(rhs)
    }

    static let evidenceKeys = ["link_verified", "link_checked"]

    /// `stripItem` of `verification.js`: the item without its live link evidence (other values untouched).
    public static func stripLinkEvidence(_ item: JSONValue) -> JSONValue {
        guard case .object(var dict) = item, evidenceKeys.contains(where: { dict[$0] != nil }) else { return item }
        for key in evidenceKeys { dict[key] = nil }
        return .object(dict)
    }

    /// `stripLinkEvidence(selections)` of `verification.js`: saved plans keep the chosen items, not this search's
    /// link evidence.
    public static func strippingLinkEvidence(_ selections: JSONValue) -> JSONValue {
        guard case .object(let dict) = selections else { return selections }
        return .object(dict.mapValues { value in
            if case .array(let items) = value { return .array(items.map(stripLinkEvidence)) }
            return stripLinkEvidence(value)
        })
    }
}

/// `applyPlanAction` of `ChatPage.jsx` (api-contract §4.2).
public enum PlanActions {
    static let arrayFields: Set<String> = ["activities", "tips", "getting_around", "itinerary_slots"]

    static func idKey(_ field: String) -> String {
        field == "tips" ? "title" : field == "itinerary_slots" ? "key" : "name"
    }

    /// Apply a chat `plan_action` (`set`, `add`, `remove`, `clear`) to the selections. Unknown actions change nothing.
    public static func apply(_ selections: JSONValue, action: String, field: String, data: JSONValue) -> JSONValue {
        let isList = arrayFields.contains(field)
        let key = idKey(field)
        switch action {
        case "clear":
            if field == "all" { return Selections.empty }
            return PlanJS.set(selections, field, isList ? [] : nil)
        case "set":
            return PlanJS.set(selections, field, data)
        case "add":
            guard isList else { return PlanJS.set(selections, field, data) }
            let list = selections[field].array ?? []
            if list.contains(where: { $0[key] == data[key] }) { return selections }
            return PlanJS.set(selections, field, .array(list + [data]))
        case "remove":
            guard isList else { return PlanJS.set(selections, field, nil) }
            return PlanJS.set(selections, field, .array((selections[field].array ?? []).filter { $0[key] != data[key] }))
        default:
            return selections
        }
    }
}
