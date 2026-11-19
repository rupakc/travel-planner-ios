import Foundation
import VoyagerModel

/// One answer of `POST /api/carbon/trip`, read leniently: a missing or odd field reads as empty, never a failure.
/// The crawler fields (`crawler_sources`, a line's `crawler_source`) are absent on an older or crawler-off backend,
/// and then nothing extra shows.
public struct CarbonReport: Sendable, Equatable {
    public struct Category: Sendable, Equatable, Identifiable {
        public var key: String
        public var kg: Double
        public var share: Double
        public var id: String { key }
    }

    /// One counted line. `params` are the backend's values as JS `String(value)` would print them.
    public struct Line: Sendable, Equatable {
        public var category: String
        public var kind: String
        public var label: String
        public var kg: Double
        public var method: String
        public var params: [String: String]
        public var crawlerSource: Source?
    }

    public struct Assumption: Sendable, Equatable {
        public var code: String
        public var text: String
        public var params: [String: String]
    }

    public struct Source: Sendable, Equatable {
        public var id: String?
        public var name: String
        public var url: URL?
        public var publisher: String?
        public var licence: String?
        public var attribution: String?
        public var licenceURL: URL?
        /// `YYYY-MM-DD` (the first ten characters of `as_of`), when given.
        public var asOf: String?
    }

    public struct RailHint: Sendable, Equatable {
        public var route: String
        public var railKm: Double
        public var savingKg: Double
    }

    public var totalKg: Double
    public var perPersonKg: Double
    public var travellers: Int
    /// Categories with something counted, in the backend's order (flights, stays, ground, food, activities).
    public var categories: [Category]
    public var lines: [Line]
    public var assumptions: [Assumption]
    public var sources: [Source]
    /// The Voyager crawler's sources, when a crawler number was used.
    public var crawlerSources: [Source]
    public var carKm: Double
    public var budgetShare: Double
    public var annualBudgetKg: Double
    /// The lower-carbon option with the largest saving, if any saves something.
    public var railHint: RailHint?

    public init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        totalKg = Self.number(json["total_kg"]) ?? 0
        perPersonKg = Self.number(json["per_person_kg"]) ?? 0
        travellers = json["travellers"].int ?? 1
        categories = (json["categories"].array ?? []).compactMap { item in
            guard let key = item["key"].string, CarbonRequest.categoryKeys.contains(key),
                  let kg = Self.number(item["kg"]), kg > 0 else { return nil }
            return Category(key: key, kg: kg, share: Self.number(item["share"]) ?? 0)
        }
        lines = (json["lines"].array ?? []).compactMap { item in
            guard item.object != nil else { return nil }
            return Line(
                category: item["category"].string ?? "", kind: item["kind"].string ?? "", label: item["label"].string ?? "",
                kg: Self.number(item["kg"]) ?? 0, method: item["method"].string ?? "", params: Self.params(item["params"]),
                crawlerSource: Self.source(item["crawler_source"]))
        }
        assumptions = (json["assumptions"].array ?? []).compactMap { item in
            guard item.object != nil else { return nil }
            return Assumption(code: item["code"].string ?? "", text: item["text"].string ?? "", params: Self.params(item["params"]))
        }
        sources = (json["sources"].array ?? []).compactMap(Self.source)
        crawlerSources = (json["crawler_sources"].array ?? []).compactMap(Self.source)
        let comparisons = json["comparisons"]
        carKm = Self.number(comparisons["car_km"]) ?? 0
        budgetShare = Self.number(comparisons["budget_share"]) ?? 0
        annualBudgetKg = Self.number(comparisons["annual_budget_kg"]).flatMap { $0 > 0 ? $0 : nil } ?? 2000
        railHint = (json["lower_carbon"].array ?? [])
            .compactMap { item -> RailHint? in
                guard let saving = Self.number(item["saving_kg"]), saving > 0 else { return nil }
                return RailHint(route: item["route"].string ?? "", railKm: Self.number(item["rail_km"]) ?? 0, savingKg: saving)
            }
            .max { $0.savingKg < $1.savingKg }
    }

    // MARK: - Reading

    private static func number(_ value: JSONValue) -> Double? {
        if case .number(let number) = value, number.isFinite { return number }
        return nil
    }

    /// A source object (it needs a name or a `source_id`); anything else is nil.
    static func source(_ value: JSONValue) -> Source? {
        guard value.object != nil, let name = value["name"].string ?? value["source_id"].string, !name.isEmpty else { return nil }
        let asOf = value["as_of"].string.flatMap { raw -> String? in
            raw.prefixMatch(of: /\d{4}-\d{2}-\d{2}/).map { String($0.output) }
        }
        return Source(
            id: value["id"].string, name: name, url: httpsURL(value["url"]), publisher: value["publisher"].string,
            licence: value["licence"].string, attribution: value["attribution"].string,
            licenceURL: httpsURL(value["licence_url"]), asOf: asOf)
    }

    private static func httpsURL(_ value: JSONValue) -> URL? {
        guard let raw = value.string, raw.lowercased().hasPrefix("https://"), let url = URL(string: raw), url.host != nil else {
            return nil
        }
        return url
    }

    /// Scalar params as JS `String(value)`; nested values are dropped.
    private static func params(_ value: JSONValue) -> [String: String] {
        var out: [String: String] = [:]
        for (key, item) in value.object ?? [:] {
            switch item {
            case .string(let text): out[key] = text
            case .number(let number): out[key] = ExportText.jsNumber(number)
            case .bool(let flag): out[key] = flag ? "true" : "false"
            default: break
            }
        }
        return out
    }
}
