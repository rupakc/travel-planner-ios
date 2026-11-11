import Foundation
import VoyagerModel

/// One-click "what if" presets (`REMIX_PRESETS`). Label and description are i18n keys in the `sections` namespace.
public struct RemixPreset: Sendable, Hashable, Identifiable {
    public let id: String
    public let emoji: String
    public var labelKey: String { "sections:remix.preset.\(id).label" }
    public var descriptionKey: String { "sections:remix.preset.\(id).description" }
}

/// Trip Remix (port of `remix.js`): transforms of a search request, plus before/after metric snapshots.
public enum Remix {
    public static let presets: [RemixPreset] = [
        RemixPreset(id: "week_later", emoji: "\u{1F4C5}"),
        RemixPreset(id: "half_budget", emoji: "\u{1F4B8}"),
        RemixPreset(id: "luxe", emoji: "\u{2728}"),
        RemixPreset(id: "slower_pace", emoji: "\u{1F9D8}"),
        RemixPreset(id: "long_weekend", emoji: "\u{26A1}"),
    ]

    /// Day number of a `YYYY-MM-DD` string (web: `new Date(str + 'T00:00:00')`); `nil` when it is not one.
    private static func day(_ value: JSONValue) -> Int? {
        guard let text = value.string, text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return nil }
        let ms = PlanJS.ms(value)
        return ms.isNaN ? nil : Int((ms / PlanJS.dayMs).rounded(.down))
    }

    private static func changes(_ sd: JSONValue, _ presetID: String) -> [String: JSONValue] {
        switch presetID {
        case "week_later":
            guard let dep = day(sd["departure_date"]) else { return [:] }
            var out: [String: JSONValue] = ["departure_date": .string(PlanJS.iso(days: dep + 7))]
            if let ret = day(sd["return_date"]) { out["return_date"] = .string(PlanJS.iso(days: ret + 7)) }
            return out
        case "half_budget":
            return sd["budget_usd"].isTruthy ? ["budget_usd": .number(PlanJS.round(PlanJS.toNumber(sd["budget_usd"]) / 2))] : [:]
        case "luxe":
            return sd["budget_usd"].isTruthy ? ["budget_usd": .number(PlanJS.round(PlanJS.toNumber(sd["budget_usd"]) * 2))] : [:]
        case "slower_pace":
            return ["pace": "relaxed"]
        case "long_weekend":
            guard let dep = day(sd["departure_date"]) else { return [:] }
            return ["return_date": .string(PlanJS.iso(days: dep + 3))]
        default:
            return [:]
        }
    }

    /// The search request after the preset; unchanged for an unknown preset or when nothing applies.
    public static func apply(_ searchData: JSONValue, presetID: String) -> JSONValue {
        guard presets.contains(where: { $0.id == presetID }) else { return searchData }
        let delta = changes(searchData, presetID)
        if delta.isEmpty { return searchData }
        var next = searchData.object ?? [:]
        for (key, value) in delta { next[key] = value }
        return .object(next)
    }

    // MARK: Metric snapshots

    private static func minPositive(_ list: JSONValue, key: String) -> JSONValue {
        let prices = (list.array ?? []).map { PlanJS.toNumber($0[key]) }.filter { $0.isFinite && $0 > 0 }
        return prices.min().map { .number($0) } ?? .null
    }

    /// `{min_flight_usd, min_hotel_nightly_usd, itinerary_total_usd, poor_weather_days}`; `null` when unknown.
    public static func snapshotMetrics(_ results: JSONValue?) -> JSONValue {
        let input = results ?? .null
        let total = PlanJS.toNumber(input["itinerary"]["total_estimated_cost_usd"])
        let days = input["weather"]["days"].array
        return [
            "min_flight_usd": minPositive(input["flights"]["results"], key: "price_usd"),
            "min_hotel_nightly_usd": minPositive(input["hotels"]["results"], key: "price_per_night_usd"),
            "itinerary_total_usd": total.isFinite && total > 0 ? .number(total) : .null,
            "poor_weather_days": days.map { .number(Double($0.filter { $0["is_poor"].isTruthy }.count)) } ?? .null,
        ]
    }

    private static let metrics: [(key: String, kind: String)] = [
        ("min_flight_usd", "usd"), ("min_hotel_nightly_usd", "usd"), ("itinerary_total_usd", "usd"), ("poor_weather_days", "count"),
    ]

    /// Rows `{key, label, kind, before, after, delta, direction (same|down|up), improved (bool|null)}` for every
    /// metric known on both sides. `label` comes from `sections:remix.metric.<key>`; lower is always better.
    public static func diffMetrics(_ before: JSONValue?, _ after: JSONValue?, translate: PlanText) -> [JSONValue] {
        metrics.compactMap { key, kind in
            guard let beforeValue = (before?[key]).flatMap({ $0.isNull ? nil : PlanJS.toNumber($0) }),
                  let afterValue = (after?[key]).flatMap({ $0.isNull ? nil : PlanJS.toNumber($0) }) else { return nil }
            let delta = afterValue - beforeValue
            return [
                "key": .string(key), "label": .string(translate("sections:remix.metric.\(key)", [:])), "kind": .string(kind),
                "before": .number(beforeValue), "after": .number(afterValue), "delta": .number(delta),
                "direction": .string(delta == 0 ? "same" : delta < 0 ? "down" : "up"),
                "improved": delta == 0 ? .null : .bool(delta < 0),
            ]
        }
    }
}
