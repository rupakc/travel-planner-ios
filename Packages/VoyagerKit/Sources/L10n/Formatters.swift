import Foundation

/// Number, currency, date and relative-time formatting in the app language (`LanguageController.current`).
/// Never throws: a non-finite number gives "—" and an unknown currency code shows "<code> <number>".
public enum Fmt {
    private static let dash = "—"
    private static let knownCurrencies: Set<String> = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    public static func number(_ value: Double, fractionDigits: Int? = nil, signed: Bool = false) -> String {
        guard value.isFinite else { return dash }
        let locale = LanguageController.current.intlLocale
        if signed {
            return value.formatted(
                .number.locale(locale).precision(.fractionLength(max(0, fractionDigits ?? 0)))
                    .sign(strategy: .always(includingZero: false)))
        }
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

    /// Month and day without the year ("Nov 4", "4. Nov."), for chart axes.
    public static func shortDate(_ date: Date) -> String {
        let locale = LanguageController.current.intlLocale
        return date.formatted(Date.FormatStyle().month(.abbreviated).day().locale(locale))
    }

    /// `currency` with the sign taken from the number (`-` or `+` placed by the locale, none for zero).
    public static func signedCurrency(_ amount: Double, code: String) -> String {
        guard amount.isFinite else { return dash }
        let locale = LanguageController.current.intlLocale
        guard knownCurrencies.contains(code.uppercased()) else {
            let style = FloatingPointFormatStyle<Double>.number.locale(locale)
                .sign(strategy: .always(includingZero: false)).precision(.fractionLength(2))
            return "\(code) \(amount.formatted(style))"
        }
        return amount.formatted(.currency(code: code.uppercased()).sign(strategy: .always(showZero: false)).locale(locale))
    }

    /// A server period `YYYY-MM` as a localised month and year ("May 2026", "mai 2026"); anything else (no month, a
    /// bad month, another shape) is returned unchanged so the card never shows less than the server sent.
    public static func monthYear(period: String) -> String {
        let parts = period.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month)
        else { return period }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return period }
        let locale = LanguageController.current.intlLocale
        var style = Date.FormatStyle().year().month(.wide).locale(locale)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
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
