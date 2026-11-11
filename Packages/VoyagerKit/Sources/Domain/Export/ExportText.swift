import Foundation
import VoyagerModel

/// JavaScript-flavoured string and truthiness helpers shared by the plan exporters, so the Swift output is
/// byte-identical to what the web builds from the same (loosely typed) JSON.
enum ExportText {
    /// `${value}` / `String(value)`.
    static func js(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .string(let text): return text
        case .number(let number): return jsNumber(number)
        case .array(let items): return items.map { $0.isNull ? "" : js($0) }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    /// `[a, b].join(sep)`: null and undefined read as empty.
    static func joinItem(_ value: JSONValue) -> String {
        value.isNull ? "" : js(value)
    }

    static func jsNumber(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        if value == value.rounded(), abs(value) < 1e21 { return value == 0 ? "0" : String(format: "%.0f", value) }
        return "\(value)"
    }

    /// `a || b`.
    static func or(_ first: JSONValue, _ second: JSONValue) -> JSONValue { first.isTruthy ? first : second }

    /// `a ?? b` (a missing key reads as `.null`).
    static func coalesce(_ first: JSONValue, _ second: JSONValue) -> JSONValue { first.isNull ? second : first }

    /// `value > 0` after JS number coercion.
    static func isPositive(_ value: JSONValue) -> Bool {
        guard let number = value.double, !number.isNaN else { return false }
        return number > 0
    }

    /// `Math.round` for the non-negative numbers used here (half rounds up).
    static func round(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }

    /// `Array.prototype.filter(Boolean).join(sep)` over optional parts.
    static func joined(_ parts: [String?], _ separator: String) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: separator)
    }

    /// `(place || '').split(',')[0].trim()`.
    static func shortPlace(_ place: JSONValue) -> String {
        let text = place.isTruthy ? js(place) : ""
        let first = text.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The URL if it is an http(s) link with a host, normalised like `new URL(value).href`
    /// ("http://example.com" becomes "http://example.com/"), else `nil` (no `javascript:`, `data:`, ...).
    static func safeURL(_ value: String?) -> String? {
        guard let value, let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        var normalised = components
        normalised.scheme = scheme
        if normalised.path.isEmpty { normalised.path = "/" }
        return normalised.string
    }

    /// USD like the web's `formatPrice`: "$2,250", "$9.90" (cents only under $100 and not whole).
    static func usd(_ amount: Double, alwaysCents: Bool = false) -> String {
        guard amount.isFinite else { return "" }
        let cents = (abs(amount) * 100).rounded(.toNearestOrAwayFromZero) / 100
        let whole = cents == cents.rounded()
        let showCents = alwaysCents || (cents < 100 && !whole)
        let body = String(format: showCents ? "%.2f" : "%.0f", cents)
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        return (amount < 0 ? "-$" : "$") + grouped(String(parts[0])) + (parts.count > 1 ? "." + parts[1] : "")
    }

    /// USD with up to two decimals and no trailing zeros ("$1,234.5"), as `Intl.NumberFormat` does with
    /// `minimumFractionDigits: 0, maximumFractionDigits: 2`.
    static func usdUpTo2(_ amount: Double) -> String {
        guard amount.isFinite else { return "$NaN" }
        var body = String(format: "%.2f", abs(amount))
        if body.hasSuffix("0") { body.removeLast() }
        if body.hasSuffix("0") { body.removeLast() }
        if body.hasSuffix(".") { body.removeLast() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        return (amount < 0 ? "-$" : "$") + grouped(String(parts[0])) + (parts.count > 1 ? "." + parts[1] : "")
    }

    private static func grouped(_ digits: String) -> String {
        var out = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { out.append(",") }
            out.append(character)
        }
        return String(out.reversed())
    }
}
