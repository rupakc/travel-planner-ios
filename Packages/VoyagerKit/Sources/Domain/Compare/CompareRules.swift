import Foundation
import VoyagerModel

/// Pure rules for trip comparison; ports of `frontend/src/utils/compare.js` (golden-tested against the web).
public enum CompareRules {
    /// One `TravelSearchRequest` per destination. Only `destination` varies; blank and duplicate
    /// (case-insensitive) destinations are dropped, multi-city fields are cleared, `num_travelers` is the party
    /// size (at least 1) and an empty return date or unparseable budget becomes `null`.
    public static func requests(form: JSONValue) -> [JSONValue] {
        var shared = form.object ?? [:]
        let rawDestinations = shared["destinations"]?.array ?? []
        shared["destinations"] = nil
        shared["destination"] = nil
        shared["extraStops"] = nil

        var seen = Set<String>()
        var unique: [String] = []
        for raw in rawDestinations {
            let destination = jsString(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = destination.lowercased()
            if destination.isEmpty || !seen.insert(key).inserted { continue }
            unique.append(destination)
        }

        let party = ["adults", "children", "seniors", "infants"].reduce(0.0) { $0 + (shared[$1]?.truthyDouble ?? 0) }
        let travellers = max(1, party)
        let budget: JSONValue
        if let raw = shared["budget_usd"], raw.isTruthy, let value = parseFloat(raw), value.isFinite {
            budget = .number(value)
        } else {
            budget = .null
        }
        let returnDate = ExportText.or(shared["return_date"] ?? .null, .null)

        return unique.map { destination in
            var request = shared
            request["num_travelers"] = .number(travellers)
            request["budget_usd"] = budget
            request["return_date"] = returnDate
            request["destination"] = .string(destination)
            request["destinations"] = .null
            request["destination_nights"] = .null
            return .object(request)
        }
    }

    /// `rowKey` -> extractor and which value is best (`min`: lowest, `max`: highest).
    private struct RowRule {
        let key: String
        let lowestWins: Bool
        let value: @Sendable (JSONValue) -> Double?

        init(_ key: String, lowestWins: Bool, value: @escaping @Sendable (JSONValue) -> Double?) {
            self.key = key
            self.lowestWins = lowestWins
            self.value = value
        }
    }

    private static let rowRules: [RowRule] = [
        // A partial total omits unknown costs, so it can't be called the cheapest.
        RowRule("estimate", lowestWins: true) { $0["estimate"]["partial"].bool == true ? nil : number($0["estimate"]["total_usd"]) },
        RowRule("flight", lowestWins: true) { number($0["flight"]["price_usd"]) },
        RowRule("hotel", lowestWins: true) { number($0["hotel"]["typical_nightly_usd"]) },
        RowRule("weather", lowestWins: true) { number($0["weather"]["poor_days"]) },
        RowRule("ease", lowestWins: false) { number($0["ease"]["total"]) },
        RowRule("safety", lowestWins: false) { number($0["ease"]["safety"]) },
        RowRule("english", lowestWins: false) { number($0["ease"]["english"]) },
        RowRule("daily", lowestWins: true) { number($0["daily_cost_usd"]) },
    ]

    /// For each numeric row, the set of column indexes holding the best value. Ties mark every tied column.
    /// Rows with fewer than two known (finite numeric) values are omitted. `summaries` is indexed by column.
    public static func bestByRow(_ summaries: [JSONValue]) -> [String: Set<Int>] {
        var out: [String: Set<Int>] = [:]
        for rule in rowRules {
            let known = summaries.enumerated().compactMap { index, summary in
                rule.value(summary).map { (index: index, value: $0) }
            }
            guard known.count >= 2 else { continue }
            let best = known.map(\.value).reduce(known[0].value) { rule.lowestWins ? min($0, $1) : max($0, $1) }
            out[rule.key] = Set(known.filter { $0.value == best }.map(\.index))
        }
        return out
    }

    /// The duration text ("2h 5m") for the caller's localised template (`misc:compare.duration`, `{{h}}h {{m}}m`)
    /// given as a function of hours and minutes; there is no default language. `nil` for a missing or non-positive
    /// duration. The minutes part rounds half up like JS `Math.round`, so 119.5 reads "1h 60m" as on the web.
    public static func durationText(minutes: Double?, format: (_ hours: Int, _ minutes: Int) -> String) -> String? {
        guard let minutes, minutes.isFinite, minutes > 0 else { return nil }
        let hours = Int((minutes / 60).rounded(.down))
        let rest = Int((minutes.truncatingRemainder(dividingBy: 60) + 0.5).rounded(.down))
        return format(hours, rest)
    }

    // MARK: - JS coercions

    private static func number(_ value: JSONValue) -> Double? {
        if case .number(let number) = value, number.isFinite { return number }
        return nil
    }

    /// `String(value)` for the strings and numbers a destination list can hold.
    private static func jsString(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number): return ExportText.jsNumber(number)
        default: return ""
        }
    }

    /// JS `parseFloat`: the longest numeric prefix of a string, or the number itself.
    private static func parseFloat(_ value: JSONValue) -> Double? {
        switch value {
        case .number(let number): return number
        case .string(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("Infinity") || text.hasPrefix("+Infinity") { return .infinity }
            if text.hasPrefix("-Infinity") { return -.infinity }
            guard let match = text.prefixMatch(of: /[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/) else { return nil }
            return Double(String(match.output.0))
        default: return nil
        }
    }
}

private extension JSONValue {
    /// `value || 0` for a number (JS: NaN, null and 0 give 0).
    var truthyDouble: Double? {
        if case .number(let number) = self, number != 0, !number.isNaN { return number }
        return nil
    }
}
