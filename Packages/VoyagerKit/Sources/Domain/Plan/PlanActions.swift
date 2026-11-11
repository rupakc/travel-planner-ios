import Foundation
import VoyagerModel

/// `applyPlanAction` of `ChatPage.jsx` (api-contract §4.2).
public enum PlanActions {
    static let arrayFields: Set<String> = ["activities", "tips", "getting_around", "itinerary_slots"]

    static func idKey(_ field: String) -> String {
        field == "tips" ? "title" : field == "itinerary_slots" ? "key" : "name"
    }

    /// Apply a chat `plan_action` (`set`, `add`, `remove`, `clear`) to the selections. Unknown actions change nothing.
    public static func apply(_ selections: JSONValue, action: String, field: String, data: JSONValue) -> JSONValue {
        let isList = arrayFields.contains(field)
        // A malformed add, or a remove from a list, without an object would match every item with a missing key.
        if action == "add" || (action == "remove" && isList), data.object == nil { return selections }
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
