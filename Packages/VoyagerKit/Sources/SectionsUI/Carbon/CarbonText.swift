import DesignSystem
import Domain
import Foundation
import L10n

/// The footprint's strings. Lines and assumptions carry a stable `kind` / `code` plus `params`, translated here as on
/// the web (`results:carbon.line.*`, `results:carbon.assume.*`); an unknown kind or code shows the backend's English
/// text, never a raw key.
enum CarbonText {
    static let lineKeys: [String: LKey] = [
        "flight_tim": K.results.carbon.line.flight_tim,
        "flight_factor": K.results.carbon.line.flight_factor,
        "hotel_nights": K.results.carbon.line.hotel_nights,
        "local_measured": K.results.carbon.line.local_measured,
        "local_estimate": K.results.carbon.line.local_estimate,
        "intercity": K.results.carbon.line.intercity,
        "meals": K.results.carbon.line.meals,
        "activity_estimate": K.results.carbon.line.activity_estimate,
    ]

    static let assumptionKeys: [String: LKey] = [
        "travellers_default": K.results.carbon.assume.travellers_default,
        "nights_default": K.results.carbon.assume.nights_default,
        "flights_cheapest": K.results.carbon.assume.flights_cheapest,
        "flights_cabin": K.results.carbon.assume.flights_cabin,
        "flights_none": K.results.carbon.assume.flights_none,
        "flight_desnz": K.results.carbon.assume.flight_desnz,
        "flight_unknown_airport": K.results.carbon.assume.flight_unknown_airport,
        "rooms_default": K.results.carbon.assume.rooms_default,
        "hotel_default": K.results.carbon.assume.hotel_default,
        "stays_none": K.results.carbon.assume.stays_none,
        "ground_default_mix": K.results.carbon.assume.ground_default_mix,
        "ground_straight_line": K.results.carbon.assume.ground_straight_line,
        "ground_per_day": K.results.carbon.assume.ground_per_day,
        "intercity_rail": K.results.carbon.assume.intercity_rail,
        "intercity_unknown": K.results.carbon.assume.intercity_unknown,
        "food_basket": K.results.carbon.assume.food_basket,
        "activities_partial": K.results.carbon.assume.activities_partial,
        "activities_unmodelled": K.results.carbon.assume.activities_unmodelled,
        "hotel_grid": K.results.carbon.assume.hotel_grid,
        "factors_newer": K.results.carbon.assume.factors_newer,
    ]

    static let dietKeys: [String: LKey] = [
        "mixed": K.results.carbon.diet.mixed,
        "meat_heavy": K.results.carbon.diet.meat_heavy,
        "pescatarian": K.results.carbon.diet.pescatarian,
        "vegetarian": K.results.carbon.diet.vegetarian,
        "vegan": K.results.carbon.diet.vegan,
    ]

    static let modeKeys: [String: LKey] = [
        "rail_national": K.results.carbon.mode.rail_national,
        "rail_international": K.results.carbon.mode.rail_international,
        "light_rail_tram": K.results.carbon.mode.light_rail_tram,
        "metro": K.results.carbon.mode.metro,
        "bus_local": K.results.carbon.mode.bus_local,
        "coach": K.results.carbon.mode.coach,
        "taxi_vehicle": K.results.carbon.mode.taxi_vehicle,
        "car_average": K.results.carbon.mode.car_average,
        "ferry_foot": K.results.carbon.mode.ferry_foot,
    ]

    static let cabinKeys: [String: LKey] = [
        "economy": K.results.carbon.cabin.economy,
        "premium_economy": K.results.carbon.cabin.premium_economy,
        "business": K.results.carbon.cabin.business,
        "first": K.results.carbon.cabin.first,
    ]

    static let categoryKeys: [String: LKey] = [
        "flights": K.results.carbon.cat.flights,
        "stays": K.results.carbon.cat.stays,
        "ground": K.results.carbon.cat.ground,
        "food": K.results.carbon.cat.food,
        "activities": K.results.carbon.cat.activities,
    ]

    static func line(_ line: CarbonReport.Line) -> String {
        guard let key = lineKeys[line.kind] else { return line.label }
        var overrides: [String: String] = [:]
        if let value = line.params["mode"] { overrides["mode"] = modeKeys[value].map { L10n.text($0) } ?? value }
        if let value = line.params["diet"] { overrides["diet"] = diet(value) }
        return fill(key, line.params, overrides)
    }

    static func assumption(_ assumption: CarbonReport.Assumption) -> String {
        guard let key = assumptionKeys[assumption.code] else { return assumption.text }
        var overrides: [String: String] = [:]
        if let value = assumption.params["diet"] { overrides["diet"] = diet(value) }
        if let value = assumption.params["cabin"] { overrides["cabin"] = cabinKeys[value].map { L10n.text($0) } ?? value }
        return fill(key, assumption.params, overrides)
    }

    static func diet(_ diet: String) -> String { dietKeys[diet].map { L10n.text($0) } ?? diet }

    static func category(_ key: String) -> String { categoryKeys[key].map { L10n.text($0) } ?? key }

    static func method(_ method: String) -> String {
        switch method {
        case "measured_tim": L10n.text(K.results.carbon.method.measured_tim)
        case "factor": L10n.text(K.results.carbon.method.factor)
        case "estimate": L10n.text(K.results.carbon.method.estimate)
        default: method
        }
    }

    static func methodFamily(_ method: String) -> Family {
        switch method {
        case "measured_tim": .emerald
        case "factor": .sky
        case "estimate": .amber
        default: .gray
        }
    }

    static func categoryFamily(_ key: String) -> Family {
        switch key {
        case "flights": .sky
        case "stays": .purple
        case "ground": .amber
        case "food": .green
        case "activities": .pink
        default: .gray
        }
    }

    /// Whole kilograms in the app language (`1,000`).
    static func kg0(_ value: Double) -> String { Fmt.number(value.rounded()) }

    /// One decimal under 10 kg (dropped when whole), whole kilograms above.
    static func kg1(_ value: Double) -> String {
        guard value < 10 else { return Fmt.number(value.rounded()) }
        let tenths = (value * 10).rounded() / 10
        return Fmt.number(tenths, fractionDigits: tenths == tenths.rounded() ? 0 : 1)
    }

    /// `YYYY-MM-DD` as a medium date with the year, in the app language.
    static func day(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: raw) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = LanguageController.current.intlLocale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    /// Exactly the key's placeholders (the catalogue checks them), from `overrides`, then `params`, else empty.
    private static func fill(_ key: LKey, _ params: [String: String], _ overrides: [String: String]) -> String {
        var args: [String: String] = [:]
        for name in key.placeholders { args[name] = overrides[name] ?? params[name] ?? "" }
        return L10n.text(key, args)
    }
}
