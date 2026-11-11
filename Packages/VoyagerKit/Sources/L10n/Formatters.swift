import Foundation

/// Number, currency, date and relative-time formatting in the app language (`LanguageController.current`).
/// Never throws: a non-finite number gives "—" and an unknown currency code shows "<code> <number>".
public enum Fmt {
    private static let dash = "—"
    private static let knownCurrencies: Set<String> = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    public static func number(_ value: Double, fractionDigits: Int? = nil) -> String {
        guard value.isFinite else { return dash }
        let locale = LanguageController.current.intlLocale
        if let digits = fractionDigits {
            return value.formatted(.number.locale(locale).precision(.fractionLength(max(0, digits))))
        }
        return value.formatted(.number.locale(locale))
    }

    public static func currency(_ amount: Double, code: String) -> String {
        guard amount.isFinite else { return dash }
        let locale = LanguageController.current.intlLocale
        guard knownCurrencies.contains(code.uppercased()) else {
            return "\(code) \(amount.formatted(.number.locale(locale)))"
        }
        return amount.formatted(.currency(code: code.uppercased()).locale(locale))
    }

    public static func date(_ date: Date, style: Date.FormatStyle.DateStyle = .abbreviated, time: Bool = false) -> String {
        let locale = LanguageController.current.intlLocale
        return date.formatted(Date.FormatStyle(date: style, time: time ? .shortened : .omitted).locale(locale))
    }

    /// `interval` is the signed offset from now in seconds (negative = in the past), like Foundation's
    /// `RelativeDateTimeFormatter`. Under 60 s either way gives the language's word for "now".
    public static func relative(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return dash }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LanguageController.current.intlLocale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        if abs(interval) < 60 { return formatter.localizedString(from: DateComponents(second: 0)) }
        return formatter.localizedString(fromTimeInterval: interval)
    }
}
