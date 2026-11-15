import Foundation

// Social ideas feed, comments and reports (`docs/Social-API.md`). Same lenient decoding as `Phase5Models.swift`.

// MARK: Ideas

public enum IdeaKind: Sendable, Hashable {
    case plan, recap
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "plan": self = .plan
        case "recap": self = .recap
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .plan: "plan"
        case .recap: "recap"
        case .unknown(let value): value
        }
    }
}

/// An idea's moderation state. `held` shows only to its author (a notice, never the text to others); `hidden` and
/// `removed` are never shown. An unknown status is treated as not published.
public enum IdeaStatus: Sendable, Hashable {
    case published, held, hidden, removed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "published": self = .published
        case "held": self = .held
        case "hidden": self = .hidden
        case "removed": self = .removed
        default: self = .unknown(rawValue)
        }
    }

    public var isPublished: Bool { self == .published }
}

public struct IdeaAuthor: Sendable, Hashable {
    public var handle: String
    public var avatarURL: String?

    public init(handle: String, avatarURL: String? = nil) {
        self.handle = handle
        self.avatarURL = avatarURL
    }
}

/// A shared plan or recap snapshot with a title and caption.
public struct Idea: JSONBacked, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: IdeaKind
    public var title: String
    public var caption: String
    public var author: IdeaAuthor
    /// Whitelisted by the server (counts, destinations, days, selected items); read keys defensively.
    public var snapshot: JSONValue
    public var likes: Int
    public var saves: Int
    public var comments: Int
    public var liked: Bool
    public var saved: Bool
    public var mine: Bool
    public var status: IdeaStatus
    public var createdAt: String?

    public init(
        id: String, kind: IdeaKind = .plan, title: String, caption: String = "", author: IdeaAuthor, snapshot: JSONValue = .null,
        likes: Int = 0, saves: Int = 0, comments: Int = 0, liked: Bool = false, saved: Bool = false, mine: Bool = false,
        status: IdeaStatus = .published, createdAt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.caption = caption
        self.author = author
        self.snapshot = snapshot
        self.likes = likes
        self.saves = saves
        self.comments = comments
        self.liked = liked
        self.saved = saved
        self.mine = mine
        self.status = status
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let id = json["id"].lenientString, !id.isEmpty, let handle = json["author"]["handle"].string, !handle.isEmpty else {
            return nil
        }
        self.init(
            id: id, kind: IdeaKind(rawValue: json["kind"].string ?? ""), title: json["title"].string ?? "",
            caption: json["caption"].string ?? "",
            author: IdeaAuthor(handle: handle, avatarURL: json["author"]["avatar_url"].string), snapshot: json["snapshot"],
            likes: json["likes"].lenientInt ?? 0, saves: json["saves"].lenientInt ?? 0, comments: json["comments"].lenientInt ?? 0,
            liked: json["liked"].lenientBool ?? false, saved: json["saved"].lenientBool ?? false,
            mine: json["mine"].lenientBool ?? false,
            // A missing status reads as published (older servers); an unknown one is not shown.
            status: json["status"].string.map(IdeaStatus.init(rawValue:)) ?? .published, createdAt: json["created_at"].string)
    }
}

/// `GET /social/feed` and `GET /social/profile/{handle}/ideas`.
public struct IdeaPage: JSONBacked, Sendable, Hashable {
    public var ideas: [Idea]
    /// Opaque (an offset for `for_you`, an id for the other scopes); nil on the last page.
    public var next: String?

    public init(ideas: [Idea] = [], next: String? = nil) {
        self.ideas = ideas
        self.next = next
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        self.init(ideas: json["ideas"].models(Idea.self), next: json["next"].cursor)
    }
}

public enum FeedScope: String, Sendable, Hashable, CaseIterable {
    case forYou = "for_you"
    case following
    case new
}

/// `POST /social/ideas`. Title at most 80 characters, caption at most 500.
public struct IdeaDraft: Encodable, Sendable, Hashable {
    public static let maxTitle = 80
    public static let maxCaption = 500

    public var planID: Int
    public var kind: IdeaKind
    public var title: String
    public var caption: String
    public var locale: String?

    public init(planID: Int, kind: IdeaKind = .plan, title: String, caption: String = "", locale: String? = nil) {
        self.planID = planID
        self.kind = kind
        self.title = title
        self.caption = caption
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case kind, title, caption, locale
        case planID = "plan_id"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(planID, forKey: .planID)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(caption, forKey: .caption)
        try container.encodeIfPresent(locale, forKey: .locale)
    }
}

/// `POST /social/ideas/{id}/save`: the remixed plan.
public struct SavedIdea: JSONBacked, Sendable, Hashable {
    public var planID: Int

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let planID = json["plan_id"].lenientInt else { return nil }
        self.planID = planID
    }
}

// MARK: Comments and reports

public struct IdeaComment: JSONBacked, Sendable, Hashable, Identifiable {
    public var id: String
    public var authorHandle: String
    public var text: String
    /// Marked helpful by the idea's author.
    public var helpful: Bool
    public var mine: Bool
    public var status: IdeaStatus
    public var createdAt: String?

    public init(
        id: String, authorHandle: String, text: String, helpful: Bool = false, mine: Bool = false,
        status: IdeaStatus = .published, createdAt: String? = nil
    ) {
        self.id = id
        self.authorHandle = authorHandle
        self.text = text
        self.helpful = helpful
        self.mine = mine
        self.status = status
        self.createdAt = createdAt
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let id = json["id"].lenientString, !id.isEmpty, let handle = json["author"]["handle"].string else { return nil }
        self.init(
            id: id, authorHandle: handle, text: json["text"].string ?? "", helpful: json["helpful"].lenientBool ?? false,
            mine: json["mine"].lenientBool ?? false, status: json["status"].string.map(IdeaStatus.init(rawValue:)) ?? .published,
            createdAt: json["created_at"].string)
    }
}

/// `GET /social/ideas/{id}/comments`, oldest first.
public struct CommentPage: JSONBacked, Sendable, Hashable {
    public var comments: [IdeaComment]
    public var next: String?

    public init(comments: [IdeaComment] = [], next: String? = nil) {
        self.comments = comments
        self.next = next
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        self.init(comments: json["comments"].models(IdeaComment.self), next: json["next"].cursor)
    }
}

public enum ReportTarget: String, Sendable, Hashable, CaseIterable {
    case idea, comment, profile
}

/// The seven reasons of the contract, in the order the report sheet lists them.
public enum ReportReason: String, Sendable, Hashable, CaseIterable {
    case spam, abuse, sexual, violence, misinformation, other
}

/// `POST /social/reports`. The note is at most 200 characters; `id` is the idea or comment id, or the profile handle.
public struct ReportRequest: Encodable, Sendable, Hashable {
    public static let maxNote = 200

    public var target: ReportTarget
    public var id: String
    public var reason: ReportReason
    public var note: String?

    public init(target: ReportTarget, id: String, reason: ReportReason, note: String? = nil) {
        self.target = target
        self.id = id
        self.reason = reason
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case target, id, reason, note
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target.rawValue, forKey: .target)
        try container.encode(id, forKey: .id)
        try container.encode(reason.rawValue, forKey: .reason)
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { try container.encode(String(trimmed.prefix(Self.maxNote)), forKey: .note) }
    }
}
