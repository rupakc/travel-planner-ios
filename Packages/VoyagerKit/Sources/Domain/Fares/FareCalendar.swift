import Foundation
import VoyagerModel

/// Date-only arithmetic on ISO `YYYY-MM-DD` strings, in UTC terms (no time zone, no DST), mirroring the
/// web's `Date.UTC(y, m - 1, d + n)` handling, including month and day overflow.
enum IsoDayMath {
    struct Civil: Equatable {
        let year: Int
        let month: Int
        let day: Int
    }

    private static func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        Int((Double(value) / Double(divisor)).rounded(.down))
    }

    /// Days since 1970-01-01 for a (year, month 1...12, day) triple; month and day may overflow like `Date.UTC`.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let yearCarry = floorDiv(month - 1, 12)
        let monthOfYear = (month - 1) - 12 * yearCarry + 1
        let shiftedYear = year + yearCarry - (monthOfYear <= 2 ? 1 : 0)
        let era = floorDiv(shiftedYear, 400)
        let yearOfEra = shiftedYear - era * 400
        let monthIndex = (monthOfYear + 9) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468 + (day - 1)
    }

    /// The civil date of a day count since 1970-01-01.
    static func civil(fromDays days: Int) -> Civil {
        let shifted = days + 719_468
        let era = floorDiv(shifted, 146_097)
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return Civil(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    /// Days since the epoch of `YYYY-MM-DD` (any digit counts, like the web's `split('-').map(Number)`), or `nil`.
    static func days(fromIso iso: String) -> Int? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else { return nil }
        return daysFromCivil(year: year, month: month, day: day)
    }

    static func iso(fromDays days: Int) -> String {
        let date = civil(fromDays: days)
        return String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    /// `iso` moved by `delta` days; `iso` itself when it does not parse.
    static func add(_ iso: String, days delta: Int) -> String {
        guard let base = days(fromIso: iso) else { return iso }
        return Self.iso(fromDays: base + delta)
    }

    static func isIsoDate(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
    }
}

/// Fare-calendar helpers; ports of `frontend/src/utils/fareCalendar.js` (golden-tested against the web).
public enum FareCalendar {
    /// Both trip dates moved by `offset` days (trip length unchanged); a missing or empty return stays `nil`.
    public static func shiftDates(departure: String, returnDate: String?, offset: Int) -> (departure: String, returnDate: String?) {
        let moved = IsoDayMath.add(departure, days: offset)
        guard let returnDate, !returnDate.isEmpty else { return (moved, nil) }
        return (moved, IsoDayMath.add(returnDate, days: offset))
    }

    /// Whole days from `from` to `to` (negative when `to` is earlier); `0` when either does not parse.
    public static func dayOffset(from: String, to: String) -> Int {
        guard let start = IsoDayMath.days(fromIso: from), let end = IsoDayMath.days(fromIso: to) else { return 0 }
        return end - start
    }

    /// Departure date of the cheapest priced entry (the first wins a tie), or `nil` when none has a price.
    public static func cheapestDeparture(_ dates: [JSONValue]) -> String? {
        var bestPrice: Double?
        var bestEntry: JSONValue = .null
        for entry in dates {
            guard let price = number(entry["cheapest_usd"]) else { continue }
            if bestPrice == nil || price < (bestPrice ?? .infinity) {
                bestPrice = price
                bestEntry = entry
            }
        }
        return bestEntry["departure_date"].string
    }

    /// Price difference of `entry` vs the selected date, or `nil` if either is unpriced.
    public static func fareDelta(_ entry: JSONValue, _ selected: JSONValue) -> Double? {
        guard let price = number(entry["cheapest_usd"]), let base = number(selected["cheapest_usd"]) else { return nil }
        return price - base
    }

    /// Calendar days from the viewer's today (the date of `now` in `timeZone`, which the caller must choose:
    /// there is no implicit current zone) to an ISO departure date; `0` for a past, missing or unparseable date.
    public static func daysUntil(_ iso: String?, now: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let iso, IsoDayMath.isIsoDate(iso), let target = IsoDayMath.days(fromIso: iso) else { return 0 }
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return 0 }
        let today = IsoDayMath.daysFromCivil(year: year, month: month, day: day)
        return max(0, target - today)
    }

    /// A finite JSON number (not a numeric string), like the web's `isNum`.
    private static func number(_ value: JSONValue) -> Double? {
        if case .number(let number) = value, number.isFinite { return number }
        return nil
    }
}
