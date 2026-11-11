import Foundation
import VoyagerModel

/// Slot keys: `"<day_number>-<time_of_day>"`, the first slot with a given time on a day; later ones with
/// the same time get `#2`, `#3` suffixes. Edits, notes, plan picks and calendar UIDs stay attached to it.
extension ItineraryLayout {
    /// The standard times of day, in order.
    public static let times = ["morning", "afternoon", "evening"]

    public static func slotKey(day: Int, timeOfDay: String) -> String {
        "\(day)-\(timeOfDay)"
    }

    /// `slotKey` over raw JSON values (the web interpolates whatever the backend sent).
    static func slotKey(_ day: JSONValue, _ timeOfDay: JSONValue) -> String {
        "\(JSCoerce.interpolate(day))-\(JSCoerce.interpolate(timeOfDay))"
    }
}

/// JavaScript-compatible string conversion for template literals over JSON values.
enum JSCoerce {
    /// `${value}` for a JSON value: integers without a fraction, `null` as `"null"`.
    static func interpolate(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .string(let text): return text
        case .number(let value): return number(value)
        case .array(let items): return items.map { $0.isNull ? "" : interpolate($0) }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    /// `${object[key]}`: an absent key reads `"undefined"`.
    static func interpolate(_ object: JSONValue, _ key: String) -> String {
        guard let value = object.object?[key] else { return "undefined" }
        return interpolate(value)
    }

    static func number(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        if value == value.rounded(), abs(value) < 1e21 {
            return value == 0 ? "0" : String(format: "%.0f", value)
        }
        return "\(value)"
    }
}
