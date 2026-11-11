import Foundation

/// Which watch family an item belongs to. `flight` is a fare watch; the rest are price watches.
public enum WatchKind: String, Codable, Sendable, Hashable, CaseIterable {
    case flight, hotel, activity, trip
}

/// Either kind of watch, as answered by patch and check calls.
public enum WatchItem: Sendable, Hashable {
    case fare(FareWatch)
    case price(PriceWatch)
}

/// The item or search data to watch (SectionsUI builds it; `WatchCreateCoordinator` sends it).
public enum WatchRequest: Sendable, Hashable {
    case fare(JSONValue)
    case hotel(JSONValue)
    case activity(JSONValue)
    case trip(JSONValue)

    public var kind: WatchKind {
        switch self {
        case .fare: .flight
        case .hotel: .hotel
        case .activity: .activity
        case .trip: .trip
        }
    }

    public var spec: JSONValue {
        switch self {
        case .fare(let value), .hotel(let value), .activity(let value), .trip(let value): value
        }
    }
}

private struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// `POST /api/price-watches` body: `{"kind": "hotel", "hotel": <spec>, plan_id, alert_mode, ...}`.
/// The spec rides under the kind's own key.
public struct NewPriceWatch: Codable, Sendable, Hashable {
    public var kind: WatchKind
    public var spec: JSONValue
    public var planId: Int?
    public var alertMode: String?
    public var targetPrice: Double?
    public var targetCurrency: String?
    public var emailEnabled: Bool?

    public init(
        kind: WatchKind, spec: JSONValue, planId: Int? = nil, alertMode: String? = nil,
        targetPrice: Double? = nil, targetCurrency: String? = nil, emailEnabled: Bool? = nil
    ) {
        self.kind = kind
        self.spec = spec
        self.planId = planId
        self.alertMode = alertMode
        self.targetPrice = targetPrice
        self.targetCurrency = targetCurrency
        self.emailEnabled = emailEnabled
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: DynamicKey.self)
        let kind = try box.decode(WatchKind.self, forKey: DynamicKey("kind"))
        self.kind = kind
        spec = (try? box.decodeIfPresent(JSONValue.self, forKey: DynamicKey(kind.rawValue))) ?? .null
        planId = try? box.decodeIfPresent(Int.self, forKey: DynamicKey("plan_id"))
        alertMode = try? box.decodeIfPresent(String.self, forKey: DynamicKey("alert_mode"))
        targetPrice = try? box.decodeIfPresent(Double.self, forKey: DynamicKey("target_price"))
        targetCurrency = try? box.decodeIfPresent(String.self, forKey: DynamicKey("target_currency"))
        emailEnabled = try? box.decodeIfPresent(Bool.self, forKey: DynamicKey("email_enabled"))
    }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: DynamicKey.self)
        try box.encode(kind, forKey: DynamicKey("kind"))
        try box.encode(spec, forKey: DynamicKey(kind.rawValue))
        try box.encodeIfPresent(planId, forKey: DynamicKey("plan_id"))
        try box.encodeIfPresent(alertMode, forKey: DynamicKey("alert_mode"))
        try box.encodeIfPresent(targetPrice, forKey: DynamicKey("target_price"))
        try box.encodeIfPresent(targetCurrency, forKey: DynamicKey("target_currency"))
        try box.encodeIfPresent(emailEnabled, forKey: DynamicKey("email_enabled"))
    }
}

/// `POST /api/fare-watches/match` and `/api/price-watches/match` body. A flight match sends the
/// trip fields at the top level (like creating a fare watch); the other kinds send
/// `{"kind", "<kind>": spec, "plan_id"}`.
public struct WatchMatchQuery: Codable, Sendable, Hashable {
    public var kind: WatchKind
    public var spec: JSONValue
    public var planId: Int?

    public init(kind: WatchKind, spec: JSONValue, planId: Int? = nil) {
        self.kind = kind
        self.spec = spec
        self.planId = planId
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: DynamicKey.self)
        if let kind = try? box.decodeIfPresent(WatchKind.self, forKey: DynamicKey("kind")) {
            self.kind = kind
            spec = (try? box.decodeIfPresent(JSONValue.self, forKey: DynamicKey(kind.rawValue))) ?? .null
        } else {
            kind = .flight
            var fields: [String: JSONValue] = [:]
            for key in box.allKeys where key.stringValue != "plan_id" {
                fields[key.stringValue] = (try? box.decode(JSONValue.self, forKey: key)) ?? .null
            }
            spec = .object(fields)
        }
        planId = try? box.decodeIfPresent(Int.self, forKey: DynamicKey("plan_id"))
    }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: DynamicKey.self)
        if kind == .flight {
            guard case .object(let fields) = spec else {
                throw EncodingError.invalidValue(spec, .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "A flight match query needs an object spec (the trip fields)"))
            }
            for key in fields.keys.sorted() { try box.encode(fields[key] ?? .null, forKey: DynamicKey(key)) }
        } else {
            try box.encode(kind, forKey: DynamicKey("kind"))
            try box.encode(spec, forKey: DynamicKey(kind.rawValue))
        }
        try box.encodeIfPresent(planId, forKey: DynamicKey("plan_id"))
    }
}
