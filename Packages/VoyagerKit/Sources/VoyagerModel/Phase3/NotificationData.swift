import Foundation

/// A drop notification's `data.drop`.
public struct DropData: Sendable, Hashable {
    public var from: Double?
    public var to: Double?
    public var amount: Double
    public var pct: Double?
    public var currency: String?
    public var targetHit: Bool
    /// Always true on the server (an estimate never drops); `AppNotification.dropData` refuses an unobserved one.
    public var observed: Bool

    public init(
        from: Double? = nil, to: Double? = nil, amount: Double, pct: Double? = nil, currency: String? = nil,
        targetHit: Bool = false, observed: Bool = true
    ) {
        self.from = from
        self.to = to
        self.amount = amount
        self.pct = pct
        self.currency = currency
        self.targetHit = targetHit
        self.observed = observed
    }

    init?(json: JSONValue) {
        guard json.object != nil, let amount = json["amount"].lenientDouble else { return nil }
        self.init(
            from: json["from"].lenientDouble, to: json["to"].lenientDouble, amount: amount, pct: json["pct"].lenientDouble,
            currency: json["currency"].lenientString, targetHit: json["target_hit"].lenientBool ?? false,
            observed: json["observed"].lenientBool ?? true)
    }
}

/// `GameDelta` exactly as in the Accounts API: `{"xp", "awards": [{"rule", "points"}], "badges": [{"id", "earned_at"}],
/// "level_up": {"from", "to"} | null}`. `null` when the game is off.
public struct GameDelta: Sendable, Hashable {
    public struct Award: Sendable, Hashable {
        public var rule: String
        public var points: Int
        public init(rule: String, points: Int) {
            self.rule = rule
            self.points = points
        }
    }

    public struct Badge: Sendable, Hashable {
        public var id: String
        public var earnedAt: String?
        public init(id: String, earnedAt: String? = nil) {
            self.id = id
            self.earnedAt = earnedAt
        }
    }

    public struct LevelUp: Sendable, Hashable {
        public var from: Int
        public var to: Int
        public init(from: Int, to: Int) {
            self.from = from
            self.to = to
        }
    }

    public var xp: Int
    public var awards: [Award]
    public var badges: [Badge]
    public var levelUp: LevelUp?

    public init(xp: Int = 0, awards: [Award] = [], badges: [Badge] = [], levelUp: LevelUp? = nil) {
        self.xp = xp
        self.awards = awards
        self.badges = badges
        self.levelUp = levelUp
    }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        let awards = (json["awards"].array ?? []).compactMap { item -> Award? in
            guard let rule = item["rule"].string else { return nil }
            return Award(rule: rule, points: item["points"].lenientInt ?? 0)
        }
        let badges = (json["badges"].array ?? []).compactMap { item -> Badge? in
            guard let id = item["id"].string else { return nil }
            return Badge(id: id, earnedAt: item["earned_at"].lenientString)
        }
        var level: LevelUp?
        if let from = json["level_up"]["from"].lenientInt, let upTo = json["level_up"]["to"].lenientInt {
            level = LevelUp(from: from, to: upTo)
        }
        self.init(xp: json["xp"].lenientInt ?? 0, awards: awards, badges: badges, levelUp: level)
    }

    /// The XP of this award alone (the sum of its awards), not the running total.
    public var awardedPoints: Int { awards.reduce(0) { $0 + $1.points } }
}

/// One watch row of a `price_digest`.
public struct DigestWatch: Sendable, Hashable {
    public var kind: WatchKind?
    public var watchId: Int?
    public var title: String?
    public var latest: Double?
    public var change7d: Double?
    public var lowest: Double?
    public var checkedAt: String?

    public init(
        kind: WatchKind? = nil, watchId: Int? = nil, title: String? = nil, latest: Double? = nil, change7d: Double? = nil,
        lowest: Double? = nil, checkedAt: String? = nil
    ) {
        self.kind = kind
        self.watchId = watchId
        self.title = title
        self.latest = latest
        self.change7d = change7d
        self.lowest = lowest
        self.checkedAt = checkedAt
    }

    init(json: JSONValue) {
        self.init(
            kind: json["kind"].string.flatMap(WatchKind.init(rawValue:)), watchId: json["watch_id"].lenientInt,
            title: json["title"].lenientString, latest: json["latest"].lenientDouble,
            change7d: json["change_7d"].lenientDouble, lowest: json["lowest"].lenientDouble,
            checkedAt: json["checked_at"].lenientString)
    }
}

/// A `price_digest` notification's `data.digest`.
public struct DigestData: Sendable, Hashable {
    public var week: String?
    public var watches: [DigestWatch]
    public var savings: Savings?

    public init(week: String? = nil, watches: [DigestWatch] = [], savings: Savings? = nil) {
        self.week = week
        self.watches = watches
        self.savings = savings
    }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        var savings: Savings?
        if !json["savings"].isNull, let data = try? JSONEncoder().encode(json["savings"]) {
            savings = try? JSONDecoder().decode(Savings.self, from: data)
        }
        self.init(
            week: json["week"].lenientString,
            watches: (json["watches"].array ?? []).filter { $0.object != nil }.map(DigestWatch.init(json:)),
            savings: savings)
    }
}

extension AppNotification {
    public static let priceDigestKind = "price_digest"

    public var isPriceDigest: Bool { kind == Self.priceDigestKind }

    /// `data.drop`, when this row carries one with an amount.
    public var dropData: DropData? {
        guard let drop = DropData(json: data["drop"]), drop.observed else { return nil }
        return drop
    }

    /// `data.game` (nil when absent or null: the game is off, or nothing was awarded and shown).
    public var gameDelta: GameDelta? { GameDelta(json: data["game"]) }

    /// `data.digest` of a `price_digest` row.
    public var digest: DigestData? { DigestData(json: data["digest"]) }

    /// `data.group_count` of a grouped push ("3 prices dropped"): the server sends it as a string.
    public var groupCount: Int? { data["group_count"].lenientInt }
}
