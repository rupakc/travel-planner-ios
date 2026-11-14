import Foundation

// Price alerts 2.0 (`docs/Alerts-API.md`): the price story, savings and the drop moment's data. Everything here is
// decoded leniently (a missing, null or wrong-typed key is nil / a default, unknown keys and unknown codes are
// ignored) and nothing is computed: verdicts, advice codes and savings are the server's, the app only shows them.

/// A number that may arrive as an Int, a Double or a numeric String (`150`, `150.5`, `"150"`).
public struct LenientNumber: Codable, Sendable, Hashable {
    public let value: Double

    public init(_ value: Double) { self.value = value }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let number = json.lenientDouble else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a number"))
        }
        value = number
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension JSONValue {
    /// A finite number, from a number or a numeric string; nil for null, blank strings and everything else.
    var lenientDouble: Double? {
        switch self {
        case .number(let value): return value.isFinite ? value : nil
        case .string(let text):
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty, let value = double, value.isFinite else { return nil }
            return value
        default: return nil
        }
    }

    var lenientInt: Int? {
        guard let value = lenientDouble, value.rounded(.towardZero) == value, abs(value) < 1e15 else { return nil }
        return Int(value)
    }

    var lenientString: String? {
        switch self {
        case .string(let text): return text
        case .number(let value):
            return value.rounded(.towardZero) == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        default: return nil
        }
    }

    var lenientBool: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value == 0 ? false : (value == 1 ? true : nil)
        case .string(let text):
            switch text.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    /// The objects of an array, each decoded on its own: a malformed element is dropped, never the whole list.
    func lossyArray<T: Decodable>(_ type: T.Type) -> [T] {
        (array ?? []).compactMap { element in
            guard let data = try? JSONEncoder().encode(element) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
    }
}

/// `{"at": "…Z", "price": 412.0}`: one observed price (never an estimate).
public struct PricePoint: Codable, Sendable, Hashable {
    public var at: String
    public var price: Double

    public init(at: String, price: Double) {
        self.at = at
        self.price = price
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let price = json["price"].lenientDouble else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A point needs a price"))
        }
        self.price = price
        at = json["at"].lenientString ?? ""
    }
}

/// The usual price range: Google's for flights (`source: "google"`), the watch's own p25..p75 otherwise (`"history"`).
public struct TypicalRange: Codable, Sendable, Hashable {
    public var low: Double
    public var high: Double
    public var source: String?

    public init(low: Double, high: Double, source: String? = nil) {
        self.low = low
        self.high = high
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let low = json["low"].lenientDouble, let high = json["high"].lenientDouble else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A range needs low and high"))
        }
        self.low = low
        self.high = high
        source = json["source"].lenientString
    }
}

/// A frozen estimate: labelled "estimate", never a point, never the latest price, never counted.
public struct StoryEstimate: Codable, Sendable, Hashable {
    public var price: Double
    public var source: String?

    public init(price: Double, source: String? = nil) {
        self.price = price
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let price = json["price"].lenientDouble else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "An estimate needs a price"))
        }
        self.price = price
        source = json["source"].lenientString
    }
}

/// The verdict of the latest price against the typical range. The server decides; `nil` hides the chip.
public enum PriceVerdict: String, Sendable, Hashable, CaseIterable {
    case great, good, typical, high
}

/// The advice codes of `PriceStory.advice`. An unknown code is kept as `.unknown` and shows no advice line.
public enum AdviceCode: Sendable, Hashable {
    case pending, checksPaused, belowTarget, nearTarget, atLowest, belowTypical, withinTypical, aboveTypical
    case steady, fewChecks
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "pending": self = .pending
        case "checks_paused": self = .checksPaused
        case "below_target": self = .belowTarget
        case "near_target": self = .nearTarget
        case "at_lowest": self = .atLowest
        case "below_typical": self = .belowTypical
        case "within_typical": self = .withinTypical
        case "above_typical": self = .aboveTypical
        case "steady": self = .steady
        case "few_checks": self = .fewChecks
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .pending: "pending"
        case .checksPaused: "checks_paused"
        case .belowTarget: "below_target"
        case .nearTarget: "near_target"
        case .atLowest: "at_lowest"
        case .belowTypical: "below_typical"
        case .withinTypical: "within_typical"
        case .aboveTypical: "above_typical"
        case .steady: "steady"
        case .fewChecks: "few_checks"
        case .unknown(let code): code
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }
}

/// `{"code": "near_target", "params": {"gap": 32.0}}`.
public struct StoryAdvice: Codable, Sendable, Hashable {
    public var code: AdviceCode
    public var params: [String: Double]

    public init(code: AdviceCode, params: [String: Double] = [:]) {
        self.code = code
        self.params = params
    }

    /// `checks_paused` and `steady`: whole days.
    public var days: Int? { params["days"].map { Int($0) } }
    /// `below_target`: target minus latest.
    public var by: Double? { params["by"] }
    /// `near_target`: latest minus target.
    public var gap: Double? { params["gap"] }
    /// `few_checks`: the number of points.
    public var n: Int? { params["n"].map { Int($0) } }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let code = json["code"].string else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Advice needs a code"))
        }
        self.code = AdviceCode(wire: code)
        var params: [String: Double] = [:]
        for (key, value) in json["params"].object ?? [:] {
            if let number = value.lenientDouble { params[key] = number }
        }
        self.params = params
    }

    public func encode(to encoder: any Encoder) throws {
        let object: JSONValue = .object([
            "code": .string(code.wire),
            "params": .object(params.mapValues { .number($0) }),
        ])
        try object.encode(to: encoder)
    }
}

/// `GET /alerts/watches/{kind}/{id}/story`.
public struct PriceStory: Codable, Sendable, Hashable {
    public var kind: WatchKind?
    public var watchId: Int
    public var currency: String?
    /// `below_target` or `any_drop`; `target` is nil in `any_drop` mode.
    public var mode: String?
    public var target: Double?
    /// Observed prices only, oldest first, at most 90.
    public var points: [PricePoint]
    public var baseline: Double?
    public var latest: PricePoint?
    public var lowest: PricePoint?
    public var typical: TypicalRange?
    public var verdict: PriceVerdict?
    public var advice: StoryAdvice?
    public var checkedAt: String?
    /// Every price is shown with this age; never present a stale price as current.
    public var checkedDaysAgo: Int?
    public var nextCheckAt: String?
    public var pendingFirstCheck: Bool
    public var estimate: StoryEstimate?
    /// The drop caught on this watch (see `Savings`), nil without one.
    public var caught: Double?
    public var livePrices: Bool

    public init(
        kind: WatchKind? = nil, watchId: Int, currency: String? = nil, mode: String? = nil, target: Double? = nil,
        points: [PricePoint] = [], baseline: Double? = nil, latest: PricePoint? = nil, lowest: PricePoint? = nil,
        typical: TypicalRange? = nil, verdict: PriceVerdict? = nil, advice: StoryAdvice? = nil, checkedAt: String? = nil,
        checkedDaysAgo: Int? = nil, nextCheckAt: String? = nil, pendingFirstCheck: Bool = false,
        estimate: StoryEstimate? = nil, caught: Double? = nil, livePrices: Bool = true
    ) {
        self.kind = kind
        self.watchId = watchId
        self.currency = currency
        self.mode = mode
        self.target = target
        self.points = points
        self.baseline = baseline
        self.latest = latest
        self.lowest = lowest
        self.typical = typical
        self.verdict = verdict
        self.advice = advice
        self.checkedAt = checkedAt
        self.checkedDaysAgo = checkedDaysAgo
        self.nextCheckAt = nextCheckAt
        self.pendingFirstCheck = pendingFirstCheck
        self.estimate = estimate
        self.caught = caught
        self.livePrices = livePrices
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let id = json["watch_id"].lenientInt else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "A story needs a watch_id"))
        }
        func decoded<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
            guard !json[key].isNull, let data = try? JSONEncoder().encode(json[key]) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        watchId = id
        kind = json["kind"].string.flatMap(WatchKind.init(rawValue:))
        currency = json["currency"].lenientString
        mode = json["mode"].lenientString
        target = json["target"].lenientDouble
        points = json["points"].lossyArray(PricePoint.self)
        baseline = json["baseline"].lenientDouble
        latest = decoded("latest", PricePoint.self)
        lowest = decoded("lowest", PricePoint.self)
        typical = decoded("typical", TypicalRange.self)
        verdict = json["verdict"].string.flatMap(PriceVerdict.init(rawValue:))
        advice = decoded("advice", StoryAdvice.self)
        checkedAt = json["checked_at"].lenientString
        checkedDaysAgo = json["checked_days_ago"].lenientInt
        nextCheckAt = json["next_check_at"].lenientString
        pendingFirstCheck = json["pending_first_check"].lenientBool ?? false
        estimate = decoded("estimate", StoryEstimate.self)
        caught = json["caught"].lenientDouble
        livePrices = json["live_prices"].lenientBool ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        func point(_ point: PricePoint?) -> JSONValue {
            point.map { .object(["at": .string($0.at), "price": .number($0.price)]) } ?? .null
        }
        func number(_ value: Double?) -> JSONValue { value.map { .number($0) } ?? .null }
        let object: JSONValue = .object([
            "kind": kind.map { .string($0.rawValue) } ?? .null,
            "watch_id": .number(Double(watchId)),
            "currency": currency.map { .string($0) } ?? .null,
            "mode": mode.map { .string($0) } ?? .null,
            "target": number(target),
            "points": .array(points.map { point($0) }),
            "baseline": number(baseline),
            "latest": point(latest),
            "lowest": point(lowest),
            "typical": typical.map {
                .object(["low": .number($0.low), "high": .number($0.high), "source": $0.source.map { .string($0) } ?? .null])
            } ?? .null,
            "verdict": verdict.map { .string($0.rawValue) } ?? .null,
            "checked_at": checkedAt.map { .string($0) } ?? .null,
            "checked_days_ago": checkedDaysAgo.map { .number(Double($0)) } ?? .null,
            "next_check_at": nextCheckAt.map { .string($0) } ?? .null,
            "pending_first_check": .bool(pendingFirstCheck),
            "estimate": estimate.map { .object(["price": .number($0.price), "source": $0.source.map { .string($0) } ?? .null]) } ?? .null,
            "caught": number(caught),
            "live_prices": .bool(livePrices),
        ])
        try object.encode(to: encoder)
    }

    /// There is at least one observed price (an estimate alone is not one).
    public var hasObservedPrice: Bool { latest != nil }
}

/// The watch with the largest drop caught.
public struct SavingsBest: Codable, Sendable, Hashable {
    public var kind: WatchKind?
    public var watchId: Int
    public var title: String?
    public var caught: Double
    public var currency: String?

    public init(kind: WatchKind? = nil, watchId: Int, title: String? = nil, caught: Double, currency: String? = nil) {
        self.kind = kind
        self.watchId = watchId
        self.title = title
        self.caught = caught
        self.currency = currency
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let caught = json["caught"].lenientDouble else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "best needs caught"))
        }
        self.caught = caught
        watchId = json["watch_id"].lenientInt ?? 0
        kind = json["kind"].string.flatMap(WatchKind.init(rawValue:))
        title = json["title"].lenientString
        currency = json["currency"].lenientString
    }
}

/// `GET /alerts/summary`: "caught a drop of $X", never "saved". USD in `totalUSD`, other currencies listed
/// separately and never converted.
public struct Savings: Codable, Sendable, Hashable {
    public static let defaultMilestones = [50, 200, 1000]

    public var totalUSD: Double
    /// Currency code to amount, only amounts above 0.
    public var byCurrency: [String: Double]
    public var dropsCaught: Int
    public var targetsHit: Int
    public var watchesActive: Int
    public var best: SavingsBest?
    public var milestones: [Int]
    /// nil once $1,000 is reached.
    public var nextMilestone: Int?
    public var progressPct: Int
    public var since: String?

    public init(
        totalUSD: Double = 0, byCurrency: [String: Double] = [:], dropsCaught: Int = 0, targetsHit: Int = 0,
        watchesActive: Int = 0, best: SavingsBest? = nil, milestones: [Int] = Savings.defaultMilestones,
        nextMilestone: Int? = 50, progressPct: Int = 0, since: String? = nil
    ) {
        self.totalUSD = totalUSD
        self.byCurrency = byCurrency
        self.dropsCaught = dropsCaught
        self.targetsHit = targetsHit
        self.watchesActive = watchesActive
        self.best = best
        self.milestones = milestones
        self.nextMilestone = nextMilestone
        self.progressPct = progressPct
        self.since = since
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard json.object != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Savings is an object"))
        }
        totalUSD = json["total_usd"].lenientDouble ?? 0
        var currencies: [String: Double] = [:]
        for (code, value) in json["by_currency"].object ?? [:] {
            if let amount = value.lenientDouble, amount > 0 { currencies[code] = amount }
        }
        byCurrency = currencies
        dropsCaught = json["drops_caught"].lenientInt ?? 0
        targetsHit = json["targets_hit"].lenientInt ?? 0
        watchesActive = json["watches_active"].lenientInt ?? 0
        if json["best"].isNull {
            best = nil
        } else if let data = try? JSONEncoder().encode(json["best"]) {
            best = try? JSONDecoder().decode(SavingsBest.self, from: data)
        } else {
            best = nil
        }
        let listed = (json["milestones"].array ?? []).compactMap(\.lenientInt)
        milestones = listed.isEmpty ? Savings.defaultMilestones : listed
        nextMilestone = json["next_milestone"].lenientInt
        progressPct = json["progress_pct"].lenientInt ?? 0
        since = json["since"].lenientString
    }

    public func encode(to encoder: any Encoder) throws {
        let object: JSONValue = .object([
            "total_usd": .number(totalUSD),
            "by_currency": .object(byCurrency.mapValues { .number($0) }),
            "drops_caught": .number(Double(dropsCaught)),
            "targets_hit": .number(Double(targetsHit)),
            "watches_active": .number(Double(watchesActive)),
            "best": best.map {
                .object([
                    "kind": $0.kind.map { .string($0.rawValue) } ?? .null, "watch_id": .number(Double($0.watchId)),
                    "title": $0.title.map { .string($0) } ?? .null, "caught": .number($0.caught),
                    "currency": $0.currency.map { .string($0) } ?? .null,
                ])
            } ?? .null,
            "milestones": .array(milestones.map { .number(Double($0)) }),
            "next_milestone": nextMilestone.map { .number(Double($0)) } ?? .null,
            "progress_pct": .number(Double(progressPct)),
            "since": since.map { .string($0) } ?? .null,
        ])
        try object.encode(to: encoder)
    }

    /// Nothing caught yet.
    public var isEmpty: Bool { totalUSD <= 0 && byCurrency.isEmpty }

    /// The non-USD amounts in a stable order (code order), for "plus €12.00" lines.
    public var currencyLines: [(code: String, amount: Double)] {
        byCurrency.keys.sorted().map { ($0, byCurrency[$0] ?? 0) }
    }
}
