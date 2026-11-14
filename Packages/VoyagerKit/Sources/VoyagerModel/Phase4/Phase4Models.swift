import Foundation

// Share links 2.0 (`docs/Sharing-API.md`). The server decides what a share reveals; the app only sends the sharer's
// choices and shows what comes back.

/// The `kind` of a share. An unknown kind (the contract adds kinds additively) is a plain link: it keeps its URL and
/// title and gets no kind-specific wording, card or text.
public enum ShareKind: Hashable, Sendable, Codable {
    case plan, recap, savings, quiz, status
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "plan": self = .plan
        case "recap": self = .recap
        case "savings": self = .savings
        case "quiz": self = .quiz
        case "status": self = .status
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .plan: "plan"
        case .recap: "recap"
        case .savings: "savings"
        case .quiz: "quiz"
        case .status: "status"
        case .unknown(let value): value
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }

    /// The registry's `kind` enum value (`plan|recap|savings|quiz|status`); nil for an unknown kind.
    public var telemetryValue: String? { isKnown ? rawValue : nil }
}

/// How much of the trip dates a share reveals. The private default hides them.
public enum ShareDates: String, Codable, Sendable, Hashable, CaseIterable {
    case hidden, month, exact
}

/// What a share reveals beyond its title, destination, length and items. Every default is private.
public struct ShareOptions: Codable, Sendable, Hashable {
    public var dates: ShareDates
    public var showOrigin: Bool
    public var showName: Bool

    public init(dates: ShareDates = .hidden, showOrigin: Bool = false, showName: Bool = false) {
        self.dates = dates
        self.showOrigin = showOrigin
        self.showName = showName
    }

    /// Anything unreadable falls back to the private default (the server does the same).
    public init(from decoder: any Decoder) throws {
        self.init(json: try JSONValue(from: decoder))
    }

    init(json: JSONValue) {
        dates = json["dates"].string.flatMap(ShareDates.init(rawValue:)) ?? .hidden
        showOrigin = json["show_origin"].lenientBool ?? false
        showName = json["show_name"].lenientBool ?? false
    }

    enum CodingKeys: String, CodingKey {
        case dates
        case showOrigin = "show_origin"
        case showName = "show_name"
    }
}

/// `POST /api/shares`. `plan_id` is for `plan`, `recap` and `status` (optional there); `session_id` for `quiz`.
public struct ShareRequest: Encodable, Sendable, Hashable {
    public var kind: ShareKind
    public var planID: Int?
    public var sessionID: String?
    public var options: ShareOptions
    public var locale: String?

    public init(
        kind: ShareKind, planID: Int? = nil, sessionID: String? = nil, options: ShareOptions = ShareOptions(), locale: String? = nil
    ) {
        self.kind = kind
        self.planID = planID
        self.sessionID = sessionID
        self.options = options
        self.locale = locale
    }

    public init(target: ShareTarget, options: ShareOptions = ShareOptions(), locale: String? = nil) {
        self.init(kind: target.kind, planID: target.planID, sessionID: target.sessionID, options: options, locale: locale)
    }

    enum CodingKeys: String, CodingKey {
        case kind, options, locale
        case planID = "plan_id"
        case sessionID = "session_id"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(planID, forKey: .planID)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(locale, forKey: .locale)
    }
}

extension ShareTarget {
    public var kind: ShareKind {
        switch self {
        case .plan: .plan
        case .recap: .recap
        case .savings: .savings
        case .quiz: .quiz
        case .status: .status
        }
    }

    /// The `plan_id` the request carries (`savings` and `quiz` have none).
    public var planID: Int? {
        switch self {
        case .plan(let id): id
        case .recap(let planID): planID
        case .status(let planID): planID
        case .savings, .quiz: nil
        }
    }

    public var sessionID: String? {
        if case .quiz(let sessionID) = self { return sessionID }
        return nil
    }
}

/// A share as `POST /shares` answers it and `GET /shares` lists it.
public struct Share: Decodable, Sendable, Hashable {
    public var token: String
    public var kind: ShareKind
    /// `nil` for `savings` (and older rows).
    public var planID: Int?
    /// The plan's name (`Price alerts` for `savings`); only in the list.
    public var title: String?
    public var url: String
    /// Absolute PNG URLs (1200x630 and 1080x1920); only in the create answer.
    public var cardLinkURL: String?
    public var cardStoryURL: String?
    public var options: ShareOptions
    public var createdAt: String?

    public init(
        token: String, kind: ShareKind, planID: Int? = nil, title: String? = nil, url: String, cardLinkURL: String? = nil,
        cardStoryURL: String? = nil, options: ShareOptions = ShareOptions(), createdAt: String? = nil
    ) {
        self.token = token
        self.kind = kind
        self.planID = planID
        self.title = title
        self.url = url
        self.cardLinkURL = cardLinkURL
        self.cardStoryURL = cardStoryURL
        self.options = options
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let token = json["token"].string, !token.isEmpty, let url = json["url"].string, !url.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "share without token or url"))
        }
        self.token = token
        self.url = url
        kind = ShareKind(rawValue: json["kind"].string ?? "")
        planID = json["plan_id"].lenientInt
        title = json["title"].string
        cardLinkURL = json["card_url"]["link"].string
        cardStoryURL = json["card_url"]["story"].string
        options = ShareOptions(json: json["options"])
        createdAt = json["created_at"].string
    }

    /// The share link as a URL; nil when the server sent something that is not one.
    public var linkURL: URL? { URL(string: url) }
}

/// A plan that still has a legacy share token (`legacy_plan_shares` of `GET /shares`).
public struct LegacyPlanShare: Decodable, Sendable, Hashable {
    public var planID: Int
    public var name: String
    public var url: String

    public init(planID: Int, name: String, url: String) {
        self.planID = planID
        self.name = name
        self.url = url
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let planID = json["plan_id"].lenientInt, let url = json["url"].string else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "legacy share"))
        }
        self.planID = planID
        self.url = url
        name = json["name"].string ?? ""
    }
}

/// `GET /api/shares`: the caller's shares newest first (at most 100) and their legacy plan links.
public struct ShareList: Decodable, Sendable, Hashable {
    public var shares: [Share]
    public var legacyPlanShares: [LegacyPlanShare]

    public init(shares: [Share] = [], legacyPlanShares: [LegacyPlanShare] = []) {
        self.shares = shares
        self.legacyPlanShares = legacyPlanShares
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        // One unreadable row never hides the others.
        shares = json["shares"].lossyArray(Share.self)
        legacyPlanShares = json["legacy_plan_shares"].lossyArray(LegacyPlanShare.self)
    }
}

/// The calls of `Sharing-API.md` that manage shares.
public protocol SharesRepository: Sendable {
    func create(_ request: ShareRequest) async throws -> Share
    func list() async throws -> ShareList
    /// Revokes at once (`204`); there is no undo.
    func revoke(token: String) async throws
}
