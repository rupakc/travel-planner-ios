import Foundation
import L10n
import VoyagerModel

/// Number and item formatting shared by the plan-tool cards. Agent JSON is loose: nothing here traps.
enum PlanToolsFormat {
    static func usd(_ amount: Double) -> String {
        guard amount.isFinite else { return "—" }
        return amount.formatted(
            .currency(code: "USD").precision(.fractionLength(0)).locale(LanguageController.current.intlLocale))
    }

    /// The amount of an item field (`price_usd` may be a number or a numeric string).
    static func amount(_ value: JSONValue) -> Double? {
        guard let number = value.double, number.isFinite else { return nil }
        return number
    }

    /// The budget total typed by the user: a finite number above zero, rounded; nil otherwise.
    static func parseTotal(_ text: String?) -> Double? {
        guard let text, let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
            value.isFinite, value > 0 else { return nil }
        return value.rounded()
    }

    static func metric(_ value: Double, kind: String) -> String {
        kind == "usd" ? usd(value) : Fmt.number(value, fractionDigits: value.rounded() == value ? 0 : 1)
    }
}
