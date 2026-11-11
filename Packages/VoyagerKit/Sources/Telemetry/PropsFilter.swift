import Foundation
import VoyagerModel

/// The registry's prop types (docs/Telemetry.md, "Prop types").
public enum PropType: Sendable, Equatable {
    case token
    case int
    case float
    case bool
    case enumeration([String])
}

/// Client-side prop filtering with the server's rules, so free text, e-mail addresses and
/// out-of-range numbers never leave the device. Pure, allocation-light, no regular expressions.
public enum PropsFilter {
    /// 2^53, the largest magnitude the server accepts for `int` and `float`.
    public static let maxMagnitude: Double = 9_007_199_254_740_992

    /// `^[A-Za-z0-9_.:/-]{1,64}$`; `nil` when `value` fails it.
    public static func token(_ value: String) -> String? {
        var count = 0
        for byte in value.utf8 {
            count += 1
            if count > 64 { return nil }
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: ":"), UInt8(ascii: "/"), UInt8(ascii: "-"):
                continue
            default:
                return nil
            }
        }
        return count == 0 ? nil : value
    }

    /// An integer within ±2^53.
    public static func int(_ value: Int) -> Int? {
        value.magnitude <= 1 << 53 ? value : nil
    }

    /// A JSON number that is a whole number within ±2^53. A JSON bool is never an int.
    public static func int(_ value: JSONValue) -> Int? {
        guard case .number(let number) = value, number.isFinite,
              number.rounded(.towardZero) == number, abs(number) <= maxMagnitude else { return nil }
        return Int(exactly: number)
    }

    /// A finite number within ±2^53.
    public static func float(_ value: Double) -> Double? {
        value.isFinite && abs(value) <= maxMagnitude ? value : nil
    }

    public static func float(_ value: JSONValue) -> Double? {
        guard case .number(let number) = value else { return nil }
        return float(number)
    }

    public static func bool(_ value: JSONValue) -> Bool? {
        if case .bool(let flag) = value { return flag }
        return nil
    }

    /// `value` when it is one of `allowed`.
    public static func `enum`(_ value: String, allowed: [String]) -> String? {
        allowed.contains(value) ? value : nil
    }

    /// Validates a loosely typed value against `type`; `nil` means "drop this prop".
    public static func value(_ value: JSONValue, as type: PropType) -> JSONValue? {
        switch type {
        case .token: return value.string.flatMap(token).map(JSONValue.string)
        case .int: return int(value).map { JSONValue.number(Double($0)) }
        case .float: return float(value).map(JSONValue.number)
        case .bool: return bool(value).map(JSONValue.bool)
        case .enumeration(let allowed):
            return value.string.flatMap { `enum`($0, allowed: allowed) }.map(JSONValue.string)
        }
    }
}
