import Foundation

// Social (`docs/Social-API.md`, frozen 2026-11-12): profiles, follows, blocks, the ideas feed, comments and reports.
// Every model decodes leniently: an unknown key is ignored, an unknown enum value keeps its text, a malformed list
// element is dropped (never the whole page), and an optional profile field is nil unless the server sent it. All user
// text here is plain; the views render it with `Text(verbatim:)` (plan ruling R13).

/// A model read from one JSON object. `init?(json:)` returns nil for anything that is not usable; `Decodable` then
/// throws, and a list drops just that element (`JSONValue.lossyArray`).
protocol JSONBacked: Decodable {
    init?(json: JSONValue)
}

extension JSONBacked {
    /// What every model's `init(from:)` calls.
    static func read(_ decoder: any Decoder) throws -> Self {
        let json = try JSONValue(from: decoder)
        guard let value = Self(json: json) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "\(Self.self) is unreadable"))
        }
        return value
    }
}

extension JSONValue {
    /// `[T]` of an array, dropping unreadable elements.
    func models<T: JSONBacked>(_ type: T.Type) -> [T] {
        (array ?? []).compactMap { T(json: $0) }
    }

    /// An opaque list cursor: a string, or a number the server may send; nil when absent or null.
    var cursor: String? { lenientString }
}

// MARK: Profile

/// Who can see a profile. An unknown value is treated as `private`, the safe reading.
public enum ProfileVisibility: String, Sendable, Hashable, CaseIterable, Codable {
    case `private`, followers, `public`

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProfileVisibility(rawValue: raw) ?? .private
    }
}

/// `GET|PUT /social/profile`: the caller's own profile. `handle == nil` means no profile yet (the defaults are shown).
/// Every extra field is an opt-in and defaults off. The own profile never carries game fields.
public struct OwnProfile: JSONBacked, Sendable, Hashable {
    public var handle: String?
    public var visibility: ProfileVisibility
    public var bio: String
    public var showAvatar: Bool
    public var showHomeCountry: Bool
    public var showCountries: Bool
    public var showLevel: Bool
    public var showBadges: Bool
    public var leaderboardOptIn: Bool
    public var homeCountry: String?
    public var createdAt: String?

    /// A user with no profile: private, nothing opted in.
    public init(
        handle: String? = nil, visibility: ProfileVisibility = .private, bio: String = "", showAvatar: Bool = false,
        showHomeCountry: Bool = false, showCountries: Bool = false, showLevel: Bool = false, showBadges: Bool = false,
        leaderboardOptIn: Bool = false, homeCountry: String? = nil, createdAt: String? = nil
    ) {
        self.handle = handle
        self.visibility = visibility
        self.bio = bio
        self.showAvatar = showAvatar
        self.showHomeCountry = showHomeCountry
        self.showCountries = showCountries
        self.showLevel = showLevel
        self.showBadges = showBadges
        self.leaderboardOptIn = leaderboardOptIn
        self.homeCountry = homeCountry
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        self.init(
            handle: json["handle"].string.flatMap { $0.isEmpty ? nil : $0 },
            visibility: json["visibility"].string.flatMap(ProfileVisibility.init(rawValue:)) ?? .private,
            bio: json["bio"].string ?? "", showAvatar: json["show_avatar"].lenientBool ?? false,
            showHomeCountry: json["show_home_country"].lenientBool ?? false,
            showCountries: json["show_countries"].lenientBool ?? false, showLevel: json["show_level"].lenientBool ?? false,
            showBadges: json["show_badges"].lenientBool ?? false,
            leaderboardOptIn: json["leaderboard_opt_in"].lenientBool ?? false,
            homeCountry: json["home_country"].string.flatMap { $0.isEmpty ? nil : $0 }, createdAt: json["created_at"].string)
    }

    public var hasProfile: Bool { handle != nil }
}

/// `PUT /social/profile`: any subset of the writable fields; only the ones set are sent.
public struct ProfilePatch: Encodable, Sendable, Hashable {
    public var handle: String?
    public var visibility: ProfileVisibility?
    public var bio: String?
    public var showAvatar: Bool?
    public var showHomeCountry: Bool?
    public var showCountries: Bool?
    public var showLevel: Bool?
    public var showBadges: Bool?
    public var leaderboardOptIn: Bool?
    public var homeCountry: String?

    public init(
        handle: String? = nil, visibility: ProfileVisibility? = nil, bio: String? = nil, showAvatar: Bool? = nil,
        showHomeCountry: Bool? = nil, showCountries: Bool? = nil, showLevel: Bool? = nil, showBadges: Bool? = nil,
        leaderboardOptIn: Bool? = nil, homeCountry: String? = nil
    ) {
        self.handle = handle
        self.visibility = visibility
        self.bio = bio
        self.showAvatar = showAvatar
        self.showHomeCountry = showHomeCountry
        self.showCountries = showCountries
        self.showLevel = showLevel
        self.showBadges = showBadges
        self.leaderboardOptIn = leaderboardOptIn
        self.homeCountry = homeCountry
    }

    enum CodingKeys: String, CodingKey {
        case handle, visibility, bio
        case showAvatar = "show_avatar"
        case showHomeCountry = "show_home_country"
        case showCountries = "show_countries"
        case showLevel = "show_level"
        case showBadges = "show_badges"
        case leaderboardOptIn = "leaderboard_opt_in"
        case homeCountry = "home_country"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(handle, forKey: .handle)
        try container.encodeIfPresent(visibility, forKey: .visibility)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encodeIfPresent(showAvatar, forKey: .showAvatar)
        try container.encodeIfPresent(showHomeCountry, forKey: .showHomeCountry)
        try container.encodeIfPresent(showCountries, forKey: .showCountries)
        try container.encodeIfPresent(showLevel, forKey: .showLevel)
        try container.encodeIfPresent(showBadges, forKey: .showBadges)
        try container.encodeIfPresent(leaderboardOptIn, forKey: .leaderboardOptIn)
        try container.encodeIfPresent(homeCountry, forKey: .homeCountry)
    }
}

/// `GET /social/handles/check`.
public struct HandleCheck: JSONBacked, Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        case invalid, reserved, taken
        case unknown(String)

        init(rawValue: String) {
            switch rawValue {
            case "invalid": self = .invalid
            case "reserved": self = .reserved
            case "taken": self = .taken
            default: self = .unknown(rawValue)
            }
        }
    }

    public var available: Bool
    public var reason: Reason?

    public init(available: Bool, reason: Reason? = nil) {
        self.available = available
        self.reason = reason
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let available = json["available"].lenientBool else { return nil }
        self.init(available: available, reason: json["reason"].string.map(Reason.init(rawValue:)))
    }
}

/// One badge on a public profile.
public struct ProfileBadge: Sendable, Hashable {
    public var id: String
    public var tier: String?

    public init(id: String, tier: String? = nil) {
        self.id = id
        self.tier = tier
    }
}

/// How the caller relates to a profile (`you`). `blocked` is false in practice: a blocked pair gets `404`.
public struct ProfileRelation: Sendable, Hashable {
    public var following: Bool
    public var pending: Bool
    public var followsYou: Bool
    public var blocked: Bool

    public init(following: Bool = false, pending: Bool = false, followsYou: Bool = false, blocked: Bool = false) {
        self.following = following
        self.pending = pending
        self.followsYou = followsYou
        self.blocked = blocked
    }

    init(json: JSONValue) {
        self.init(
            following: json["following"].lenientBool ?? false, pending: json["pending"].lenientBool ?? false,
            followsYou: json["follows_you"].lenientBool ?? false, blocked: json["blocked"].lenientBool ?? false)
    }
}

/// `GET /social/profile/{handle}`. The optional fields are nil unless the owner opted in (`level` and `badges` also need
/// the owner not to hide the game); a `followers` profile shows only the handle and counts to non-followers.
public struct PublicProfile: JSONBacked, Sendable, Hashable {
    public var handle: String
    public var bio: String
    public var avatarURL: String?
    public var homeCountry: String?
    public var countries: [String]?
    public var level: Int?
    public var badges: [ProfileBadge]?
    public var ideasCount: Int
    public var followersCount: Int
    public var followingCount: Int
    public var you: ProfileRelation

    public init(
        handle: String, bio: String = "", avatarURL: String? = nil, homeCountry: String? = nil, countries: [String]? = nil,
        level: Int? = nil, badges: [ProfileBadge]? = nil, ideasCount: Int = 0, followersCount: Int = 0, followingCount: Int = 0,
        you: ProfileRelation = ProfileRelation()
    ) {
        self.handle = handle
        self.bio = bio
        self.avatarURL = avatarURL
        self.homeCountry = homeCountry
        self.countries = countries
        self.level = level
        self.badges = badges
        self.ideasCount = ideasCount
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.you = you
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let handle = json["handle"].string, !handle.isEmpty else { return nil }
        let badges = json["badges"].array.map { items in
            items.compactMap { item -> ProfileBadge? in
                item["id"].lenientString.map { ProfileBadge(id: $0, tier: item["tier"].lenientString) }
            }
        }
        self.init(
            handle: handle, bio: json["bio"].string ?? "", avatarURL: json["avatar_url"].string,
            homeCountry: json["home_country"].string,
            countries: json["countries"].array.map { $0.compactMap(\.string) }, level: json["level"].lenientInt, badges: badges,
            ideasCount: json["ideas_count"].lenientInt ?? 0, followersCount: json["followers_count"].lenientInt ?? 0,
            followingCount: json["following_count"].lenientInt ?? 0, you: ProfileRelation(json: json["you"]))
    }
}

// MARK: Follow and block

/// `PUT /social/follow/{handle}`: a `followers` profile answers `pending` until its owner accepts. An unknown state is
/// read as `pending` (not yet following), the cautious reading.
public enum FollowState: String, Sendable, Hashable {
    case following, pending
}

public struct FollowAnswer: JSONBacked, Sendable, Hashable {
    public var state: FollowState

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        state = json["state"].string.flatMap(FollowState.init(rawValue:)) ?? .pending
    }
}

/// A pending follow request on the caller's own profile.
public struct FollowRequest: JSONBacked, Sendable, Hashable {
    public var handle: String
    public var createdAt: String?

    public init(handle: String, createdAt: String? = nil) {
        self.handle = handle
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let handle = json["handle"].string, !handle.isEmpty else { return nil }
        self.init(handle: handle, createdAt: json["created_at"].string)
    }
}

public struct FollowRequestList: JSONBacked, Sendable, Hashable {
    public var requests: [FollowRequest]

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        requests = json["requests"].models(FollowRequest.self)
    }
}

/// A user in a followers, following or blocks list: a handle and nothing else.
public struct HandleUser: JSONBacked, Sendable, Hashable {
    public var handle: String

    public init(handle: String) {
        self.handle = handle
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let handle = json["handle"].string, !handle.isEmpty else { return nil }
        self.handle = handle
    }
}

/// `GET /social/followers|following` (cursor paged) and `GET /social/blocks` (no `next`).
public struct UserPage: JSONBacked, Sendable, Hashable {
    public var users: [HandleUser]
    /// Opaque; nil on the last page.
    public var next: String?

    public init(users: [HandleUser] = [], next: String? = nil) {
        self.users = users
        self.next = next
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        self.init(users: json["users"].models(HandleUser.self), next: json["next"].cursor)
    }
}
