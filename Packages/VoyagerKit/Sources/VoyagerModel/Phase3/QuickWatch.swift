import Foundation

/// Where a one-tap watch was started (`surface` of `POST /alerts/quick-watch`).
public enum QuickWatchSurface: String, Codable, Sendable, Hashable {
    case results, chat, trip, suggest
}

/// `POST /alerts/quick-watch` body. A flight `spec` holds the `POST /fare-watches` trip fields; the other kinds hold
/// their `POST /price-watches` `spec`.
public struct QuickWatchRequest: Codable, Sendable, Hashable {
    public var kind: WatchKind
    /// 1 to 120 characters.
    public var title: String
    /// At most 160 characters.
    public var subtitle: String?
    public var spec: JSONValue
    public var planId: Int?
    public var surface: QuickWatchSurface

    public init(
        kind: WatchKind, title: String, subtitle: String? = nil, spec: JSONValue, planId: Int? = nil,
        surface: QuickWatchSurface
    ) {
        self.kind = kind
        self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        self.subtitle = subtitle.map { String($0.prefix(160)) }
        self.spec = spec
        self.planId = planId
        self.surface = surface
    }

    /// The title must be 1 to 120 characters (the server answers `422 spec_invalid` otherwise).
    public var isValid: Bool { !title.isEmpty }

    enum CodingKeys: String, CodingKey {
        case kind, title, subtitle, spec
        case planId = "plan_id"
        case surface
    }
}

/// `201 {"kind", "watch", "existing": false}`; a match of an existing active watch answers `200` with `existing: true`.
/// The new watch is pending (`pendingFirstCheck`, `lastPrice == nil`, email off).
public struct QuickWatchResult: Decodable, Sendable, Hashable {
    public var kind: WatchKind
    public var watch: WatchItem
    public var existing: Bool

    public init(kind: WatchKind, watch: WatchItem, existing: Bool) {
        self.kind = kind
        self.watch = watch
        self.existing = existing
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let kind = json["kind"].string.flatMap(WatchKind.init(rawValue:)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown watch kind"))
        }
        let data = try JSONEncoder().encode(json["watch"])
        self.kind = kind
        watch = kind == .flight
            ? .fare(try JSONDecoder().decode(FareWatch.self, from: data))
            : .price(try JSONDecoder().decode(PriceWatch.self, from: data))
        existing = json["existing"].lenientBool ?? false
    }

    public var watchID: Int {
        switch watch {
        case .fare(let value): value.id
        case .price(let value): value.id
        }
    }
}

/// `POST /alerts/watches/{kind}/{id}/advice` (flights only): a cached AI tip.
public struct AdviceTip: Decodable, Sendable, Hashable {
    public var tip: String
    public var source: String?
    public var generatedAt: String?
    public var cached: Bool

    public init(tip: String, source: String? = "ai", generatedAt: String? = nil, cached: Bool = false) {
        self.tip = tip
        self.source = source
        self.generatedAt = generatedAt
        self.cached = cached
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let tip = json["tip"].string else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A tip needs text"))
        }
        self.tip = tip
        source = json["source"].lenientString
        generatedAt = json["generated_at"].lenientString
        cached = json["cached"].lenientBool ?? false
    }
}

/// Why a watch is suggested; an unknown reason keeps the row (without a reason line).
public enum SuggestionReason: Sendable, Hashable {
    case selectedInPlan, tripTotal, departureSoon
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "selected_in_plan": self = .selectedInPlan
        case "trip_total": self = .tripTotal
        case "departure_soon": self = .departureSoon
        default: self = .unknown(wire)
        }
    }
}

/// One of at most five suggested watches for a saved plan.
public struct WatchSuggestion: Decodable, Sendable, Hashable {
    public var kind: WatchKind
    public var title: String
    public var subtitle: String?
    public var spec: JSONValue
    public var reason: SuggestionReason
    public var alreadyWatching: Bool

    public init(
        kind: WatchKind, title: String, subtitle: String? = nil, spec: JSONValue = .null,
        reason: SuggestionReason = .selectedInPlan, alreadyWatching: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.spec = spec
        self.reason = reason
        self.alreadyWatching = alreadyWatching
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let kind = json["kind"].string.flatMap(WatchKind.init(rawValue:)), let title = json["title"].string else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a suggestion"))
        }
        self.kind = kind
        self.title = title
        subtitle = json["subtitle"].lenientString
        spec = json["spec"]
        reason = SuggestionReason(wire: json["reason"].string ?? "")
        alreadyWatching = json["already_watching"].lenientBool ?? false
    }
}

/// `GET /alerts/suggestions?plan_id=`.
public struct WatchSuggestions: Decodable, Sendable, Hashable {
    public var suggestions: [WatchSuggestion]
    public var livePrices: Bool

    public init(suggestions: [WatchSuggestion] = [], livePrices: Bool = true) {
        self.suggestions = suggestions
        self.livePrices = livePrices
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        suggestions = json["suggestions"].lossyArray(WatchSuggestion.self)
        livePrices = json["live_prices"].lenientBool ?? true
    }
}
