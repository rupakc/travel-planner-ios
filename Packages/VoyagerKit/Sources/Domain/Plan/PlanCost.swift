import Foundation
import VoyagerModel

/// Translates a web i18n key (`"plan:best.reason.cheapestFare"`) with its interpolation values.
/// Domain has no catalogue of its own: the UI passes `L10n`; the default returns the key.
public typealias PlanText = @Sendable (_ key: String, _ params: [String: String]) -> String

/// Plan helpers that need no translation return plain data; the ones that build a sentence take a `PlanText`.
public let planKeyText: PlanText = { key, _ in key }

/// JS-compatible primitives shared by the plan ports (`Math.round`, `Number(x)`, `new Date(str)`, `String(x)`).
enum PlanJS {
    static let dayMs: Double = 86_400_000

    /// `Math.round`: halves go up.
    static func round(_ x: Double) -> Double {
        guard x.isFinite else { return x }
        let down = x.rounded(.down)
        return x - down >= 0.5 ? down + 1 : down
    }

    /// `Number(v)`; `NaN` when JS would give `NaN`.
    static func toNumber(_ value: JSONValue?) -> Double {
        switch value ?? .null {
        case .null: return 0
        case .bool(let flag): return flag ? 1 : 0
        case .number(let number): return number
        case .string: return value?.double ?? .nan
        case .array(let items):
            // `Number([])` is 0 and `Number([x])` is `Number(String(x))`; longer arrays are `NaN`.
            switch items.count {
            case 0: return 0
            case 1:
                switch items[0] {
                case .null: return 0
                case .number(let number): return number
                case .string: return items[0].double ?? .nan
                default: return .nan
                }
            default: return .nan
            }
        case .object: return .nan
        }
    }

    /// The web's `num()`: a number or a non-blank numeric string, finite; otherwise `nil`.
    static func num(_ value: JSONValue?) -> Double? {
        switch value ?? .null {
        case .number(let number): return number.isFinite ? number : nil
        case .string(let text):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            guard let number = value?.double, number.isFinite else { return nil }
            return number
        default: return nil
        }
    }

    static func positive(_ value: JSONValue?) -> Double? {
        guard let number = num(value), number > 0 else { return nil }
        return number
    }

    /// planHelpers `price()`: finite and > 0, else 0.
    static func price(_ value: JSONValue?) -> Double {
        let number = toNumber(value)
        return number.isFinite && number > 0 ? number : 0
    }

    /// `x ?? fallback` for `null` / missing.
    static func coalesce(_ value: JSONValue?, _ fallback: JSONValue?) -> JSONValue {
        if let value, !value.isNull { return value }
        return fallback ?? .null
    }

    /// `String(v)` for the primitives the web joins into keys (`null` is `''` through `Array.join`).
    static func string(_ value: JSONValue?) -> String {
        switch value ?? .null {
        case .null: return ""
        case .bool(let flag): return flag ? "true" : "false"
        case .string(let text): return text
        case .number(let number): return numberString(number)
        case .array(let items): return items.map { string($0) }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    static func numberString(_ number: Double) -> String {
        if number.isNaN { return "NaN" }
        if number.isInfinite { return number < 0 ? "-Infinity" : "Infinity" }
        if number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
        return "\(number)"
    }

    /// `String(v ?? '').split(',')[0].trim().toLowerCase()`.
    static func cityKey(_ value: JSONValue?) -> String {
        let text = string(value)
        let head = text.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return head.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `listOf(section)`: `section.results` when the section has no error, without falsy entries.
    static func listOf(_ section: JSONValue?) -> [JSONValue] {
        guard let section, section.isTruthy, !section["error"].isTruthy, let results = section["results"].array else { return [] }
        return results.filter(\.isTruthy)
    }

    static func set(_ object: JSONValue, _ key: String, _ value: JSONValue) -> JSONValue {
        var dict = object.object ?? [:]
        dict[key] = value
        return .object(dict)
    }

    static func sortBy<T>(_ items: [T], _ comparators: [(T, T) -> Double]) -> [T] {
        items.enumerated().sorted { lhs, rhs in
            for compare in comparators {
                let order = compare(lhs.element, rhs.element)
                if order != 0 && !order.isNaN { return order < 0 }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Unknown numbers sort last.
    static func byAsc<T>(_ get: @escaping (T) -> Double?) -> (T, T) -> Double {
        { lhs, rhs in
            switch (get(lhs), get(rhs)) {
            case (nil, nil): return 0
            case (nil, _): return 1
            case (_, nil): return -1
            case (let x?, let y?): return x - y
            }
        }
    }

    static func byDesc<T>(_ get: @escaping (T) -> Double?) -> (T, T) -> Double {
        { lhs, rhs in
            switch (get(lhs), get(rhs)) {
            case (nil, nil): return 0
            case (nil, _): return 1
            case (_, nil): return -1
            case (let x?, let y?): return y - x
            }
        }
    }

    static func median(_ numbers: [Double]) -> Double {
        let value = numbers.sorted()
        let mid = value.count / 2
        return value.count % 2 == 1 ? value[mid] : (value[mid - 1] + value[mid]) / 2
    }

    // MARK: Dates

    /// Days since 1970-01-01 of a proleptic Gregorian date; days past the end of the month roll over.
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    struct CivilDate { let year: Int; let month: Int; let day: Int }

    static func civil(fromDays z0: Int) -> CivilDate {
        let shifted = z0 + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let doe = shifted - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
        return CivilDate(year: year, month: month, day: day)
    }

    nonisolated(unsafe) private static let isoPattern =
        /(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?(Z|[+-]\d{2}:?\d{2})?)?/

    /// `new Date(str).getTime()` for ISO `YYYY-MM-DD` and `YYYY-MM-DDTHH:mm[:ss[.sss]][Z|±hh:mm]`.
    /// A date without a zone is read as UTC (the web reads date-only as UTC too). `NaN` otherwise.
    static func ms(_ value: JSONValue?) -> Double {
        guard let text = value?.string?.trimmingCharacters(in: .whitespaces),
              let match = text.wholeMatch(of: isoPattern) else { return .nan }
        guard let y = Int(match.1), let mo = Int(match.2), let day = Int(match.3),
              (1...12).contains(mo), (1...31).contains(day) else { return .nan }
        var seconds = Double(daysFromCivil(y, mo, day)) * 86_400
        if let hh = match.4, let mm = match.5 {
            guard let hour = Int(hh), let mi = Int(mm), hour <= 24, mi < 60 else { return .nan }
            seconds += Double(hour * 3600 + mi * 60)
            if let ss = match.6 { guard let secs = Int(ss), secs < 60 else { return .nan }; seconds += Double(secs) }
            var fraction = 0.0
            if let frac = match.7 { fraction = (Double("0." + frac) ?? 0) }
            if let zone = match.8, zone != "Z" {
                let sign: Double = zone.hasPrefix("-") ? -1 : 1
                let digits = zone.dropFirst().filter(\.isNumber)
                guard digits.count == 4, let zh = Int(digits.prefix(2)), let zm = Int(digits.suffix(2)) else { return .nan }
                seconds -= sign * Double(zh * 3600 + zm * 60)
            }
            return (seconds + fraction) * 1000
        }
        return seconds * 1000
    }

    /// `YYYY-MM-DD` of a day count.
    static func iso(days: Int) -> String {
        let date = civil(fromDays: days)
        return String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }
}

/// `$1,234` (USD, no fraction digits) like the web's `fmtNumber(Math.round(n), {style:'currency'...})`.
public enum PlanFormat {
    public static func usd0(_ number: Double, locale: Locale = Locale(identifier: "en_US")) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: PlanJS.round(number))) ?? "$\(Int(PlanJS.round(number)))"
    }
}

/// Port of `planHelpers.js` cost helpers.
public enum PlanCost {
    /// Per-category split of the plan's cost, biggest first (`[{key, label, amount}]`): flights, hotel,
    /// activities, SIM. Only categories with a positive amount are included.
    public static func breakdown(_ selections: JSONValue, searchData: JSONValue? = nil) -> JSONValue {
        let flightsTotal = (selections["flights"].array ?? []).reduce(0.0) { $0 + PlanJS.price($1["price_usd"]) }
        let activitiesTotal = (selections["activities"].array ?? []).reduce(0.0) { $0 + PlanJS.price($1["price_usd"]) }
        struct Part {
            let key: String
            let label: String
            let amount: Double
        }
        let parts = [
            Part(key: "flights", label: "Flights", amount: PlanJS.price(selections["flight"]["price_usd"]) + flightsTotal),
            Part(key: "hotel", label: "Hotel", amount: hotelCost(selections["hotel"], searchData)),
            Part(key: "activities", label: "Activities", amount: activitiesTotal),
            Part(key: "sim", label: "SIM / eSIM", amount: PlanJS.price(selections["sim"]["price_usd"])),
        ]
        let sorted = PlanJS.sortBy(parts.filter { $0.amount > 0 }, [{ first, second in second.amount - first.amount }])
        return .array(sorted.map { ["key": .string($0.key), "label": .string($0.label), "amount": .number($0.amount)] })
    }

    public static func total(_ selections: JSONValue, searchData: JSONValue? = nil) -> Double {
        (breakdown(selections, searchData: searchData).array ?? []).reduce(0.0) { $0 + ($1["amount"].double ?? 0) }
    }

    /// `"under"` / `"over"`, or `nil` without a budget or a cost.
    public static func budgetStatus(cost: Double, budget: Double?) -> String? {
        guard let budget, budget != 0, !budget.isNaN, cost > 0 else { return nil }
        return budget - cost >= 0 ? "under" : "over"
    }

    /// `{status, amount, label}` like `getBudgetStatus`; `label` is built from `plan:util.budgetUnder|Over`.
    public static func budgetStatusDetail(
        cost: Double, budget: JSONValue?, translate: PlanText = planKeyText, locale: Locale = Locale(identifier: "en_US")
    ) -> JSONValue {
        let value = PlanJS.toNumber(budget)
        guard budget?.isTruthy == true, value != 0, !value.isNaN, cost > 0 else { return .null }
        let diff = value - cost
        let status = diff >= 0 ? "under" : "over"
        let amount = abs(diff)
        let label = translate("plan:util.budget\(diff >= 0 ? "Under" : "Over")", ["amount": PlanFormat.usd0(amount, locale: locale)])
        return ["status": .string(status), "amount": .number(PlanJS.round(amount)), "label": .string(label)]
    }

    static func hotelCost(_ hotel: JSONValue?, _ searchData: JSONValue?) -> Double {
        guard let hotel, hotel.isTruthy else { return 0 }
        let total = PlanJS.price(hotel["total_price_usd"])
        if total != 0 { return total }
        var nights = 7.0
        if let sd = searchData, sd["return_date"].isTruthy, sd["departure_date"].isTruthy {
            let raw = (PlanJS.ms(sd["return_date"]) - PlanJS.ms(sd["departure_date"])) / PlanJS.dayMs
            nights = raw.isNaN ? .nan : max(1, raw)
        }
        return PlanJS.price(hotel["price_per_night_usd"]) * nights
    }
}
