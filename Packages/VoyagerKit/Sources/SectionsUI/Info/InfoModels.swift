import Foundation
import VoyagerModel

/// Travel Ease grade (api-contract 3.4.17): green at 71 and above, amber at 41 and above, else red.
public enum ConfidenceGrade: String, Sendable, Equatable {
    case green, amber, red

    public static func grade(total: Double) -> ConfidenceGrade {
        if total >= 71 { return .green }
        if total >= 41 { return .amber }
        return .red
    }

    /// The grade for a `confidence` payload: derived from `total` (the backend's `grade` agrees; the total wins
    /// so an odd `grade` string never mislabels the score).
    public static func grade(of data: JSONValue) -> ConfidenceGrade {
        if let total = data["total"].double, total.isFinite { return grade(total: total) }
        return ConfidenceGrade(rawValue: data["grade"].string ?? "") ?? .red
    }
}

/// Packing list state kept in `selections.packing_list` (as the web's `buildPlanState`): `checked_items` maps
/// `"<category>::<item>"` to a bool, `custom_items` maps a category to the user's own items.
public enum PackingState {
    public static func key(category: String, item: String) -> String { "\(category)::\(item)" }

    /// The checked keys stored on `data` (a saved list carries `checked_items`).
    public static func checked(in data: JSONValue) -> Set<String> {
        var keys = Set<String>()
        for (key, value) in data["checked_items"].object ?? [:] where value.bool == true { keys.insert(key) }
        return keys
    }

    public static func custom(in data: JSONValue) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (category, value) in data["custom_items"].object ?? [:] {
            result[category] = (value.array ?? []).compactMap { $0.string }
        }
        return result
    }

    /// The object saved into `selections.packing_list`.
    public static func payload(data: JSONValue, checked: Set<String>, custom: [String: [String]]) -> JSONValue {
        var checkedObject: [String: JSONValue] = [:]
        for key in checked.sorted() { checkedObject[key] = .bool(true) }
        var customObject: [String: JSONValue] = [:]
        for (category, items) in custom where !items.isEmpty { customObject[category] = .array(items.map { .string($0) }) }
        let base = Int(data["total_items"].double ?? 0)
        let extra = custom.values.reduce(0) { $0 + $1.count }
        return .object([
            "categories": data["categories"],
            "luggage_note": data["luggage_note"],
            "checked_items": .object(checkedObject),
            "custom_items": .object(customObject),
            "total_items": .number(Double(base + extra)),
            "checked_count": .number(Double(checked.count)),
        ])
    }
}

/// One emergency card: single-city data is one card, multi-city data (`cities[]`) is one card per city.
public struct EmergencyCardEntry: Sendable, Equatable {
    public let city: String?
    public let data: JSONValue
}

public enum EmergencyCards {
    public static func entries(from data: JSONValue) -> [EmergencyCardEntry] {
        if let cities = data["cities"].array, !cities.isEmpty {
            return cities.compactMap { entry in
                entry.object == nil ? nil : EmergencyCardEntry(city: Info.text(entry["city"]), data: entry)
            }
        }
        return data.object == nil ? [] : [EmergencyCardEntry(city: nil, data: data)]
    }
}

/// WMO weather code to an SF Symbol.
enum WeatherSymbol {
    static func name(code: Int?) -> String {
        switch code ?? -1 {
        case 0: "sun.max"
        case 1, 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...57: "cloud.drizzle"
        case 61...67, 80...82: "cloud.rain"
        case 71...77, 85, 86: "cloud.snow"
        case 95...99: "cloud.bolt.rain"
        default: "cloud.sun"
        }
    }
}
