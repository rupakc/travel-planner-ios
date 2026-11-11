import Foundation

/// A user row from `/api/admin/users` (no password hash).
public struct AdminUser: Codable, Sendable, Hashable {
    public var id: Int?
    public var username: String
    public var email: String?
    public var isAdmin: Bool?
    public var isFirstLogin: Bool?
    public var isActive: Bool?
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: Int? = nil,
        username: String,
        email: String? = nil,
        isAdmin: Bool? = nil,
        isFirstLogin: Bool? = nil,
        isActive: Bool? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.isAdmin = isAdmin
        self.isFirstLogin = isFirstLogin
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case isAdmin = "is_admin"
        case isFirstLogin = "is_first_login"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = box.lInt(.id)
        username = try box.reqString(.username)
        email = box.lString(.email)
        isAdmin = box.lBool(.isAdmin)
        isFirstLogin = box.lBool(.isFirstLogin)
        isActive = box.lBool(.isActive)
        createdAt = box.lString(.createdAt)
        updatedAt = box.lString(.updatedAt)
    }
}

/// `POST /api/admin/users`: the password is temporary.
public struct NewAdminUser: Codable, Sendable, Hashable {
    public var username: String
    public var password: String
    public var email: String?
    public var isAdmin: Bool?

    public init(username: String, password: String, email: String? = nil, isAdmin: Bool? = nil) {
        self.username = username
        self.password = password
        self.email = email
        self.isAdmin = isAdmin
    }

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case email
        case isAdmin = "is_admin"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        username = try box.reqString(.username)
        password = try box.reqString(.password)
        email = box.lString(.email)
        isAdmin = box.lBool(.isAdmin)
    }
}

/// A row of `GET /api/admin/feedback`.
public struct FeedbackEntry: Codable, Sendable, Hashable {
    public var id: String?
    public var username: String?
    public var page: String?
    public var rating: Int?
    public var category: String?
    public var message: String?
    public var metadata: JSONValue?
    public var createdAt: String?

    public init(
        id: String? = nil,
        username: String? = nil,
        page: String? = nil,
        rating: Int? = nil,
        category: String? = nil,
        message: String? = nil,
        metadata: JSONValue? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.username = username
        self.page = page
        self.rating = rating
        self.category = category
        self.message = message
        self.metadata = metadata
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case page
        case rating
        case category
        case message
        case metadata
        case createdAt = "created_at"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = box.lString(.id)
        username = box.lString(.username)
        page = box.lString(.page)
        rating = box.lInt(.rating)
        category = box.lString(.category)
        message = box.lString(.message)
        metadata = box.lAny(JSONValue.self, .metadata)
        createdAt = box.lString(.createdAt)
    }
}

public struct TelemetryDay: Codable, Sendable, Hashable {
    public var day: String?
    public var users: Int?
    public var sessions: Int?
    public var events: Int?

    public init(day: String? = nil, users: Int? = nil, sessions: Int? = nil, events: Int? = nil) {
        self.day = day
        self.users = users
        self.sessions = sessions
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case day
        case users
        case sessions
        case events
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        day = box.lString(.day)
        users = box.lInt(.users)
        sessions = box.lInt(.sessions)
        events = box.lInt(.events)
    }
}

public struct TelemetryTopEvent: Codable, Sendable, Hashable {
    public var event: String?
    public var events: Int?

    public init(event: String? = nil, events: Int? = nil) {
        self.event = event
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case event
        case events
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        event = box.lString(.event)
        events = box.lInt(.events)
    }
}

public struct TelemetryTopScreen: Codable, Sendable, Hashable {
    public var route: String?
    public var views: Int?

    public init(route: String? = nil, views: Int? = nil) {
        self.route = route
        self.views = views
    }

    enum CodingKeys: String, CodingKey {
        case route
        case views
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        route = box.lString(.route)
        views = box.lInt(.views)
    }
}

/// `GET /api/admin/telemetry/summary`.
public struct TelemetrySummary: Codable, Sendable, Hashable {
    public var days: [TelemetryDay]
    public var topEvents: [TelemetryTopEvent]
    public var topScreens: [TelemetryTopScreen]
    public var users7d: Int?

    public init(
        days: [TelemetryDay] = [],
        topEvents: [TelemetryTopEvent] = [],
        topScreens: [TelemetryTopScreen] = [],
        users7d: Int? = nil
    ) {
        self.days = days
        self.topEvents = topEvents
        self.topScreens = topScreens
        self.users7d = users7d
    }

    enum CodingKeys: String, CodingKey {
        case days
        case topEvents = "top_events"
        case topScreens = "top_screens"
        case users7d = "users_7d"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        days = box.lAny([TelemetryDay].self, .days) ?? []
        topEvents = box.lAny([TelemetryTopEvent].self, .topEvents) ?? []
        topScreens = box.lAny([TelemetryTopScreen].self, .topScreens) ?? []
        users7d = box.lInt(.users7d)
    }
}
