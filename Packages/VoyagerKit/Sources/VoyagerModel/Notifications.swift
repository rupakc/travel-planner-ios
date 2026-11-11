import Foundation

/// A row of `GET /api/notifications`.
public struct AppNotification: Codable, Sendable, Hashable {
    public var id: Int
    public var kind: String?
    public var title: String?
    public var body: String?
    public var data: JSONValue
    public var createdAt: String?
    public var readAt: String?
    public var emailedAt: String?

    public init(
        id: Int,
        kind: String? = nil,
        title: String? = nil,
        body: String? = nil,
        data: JSONValue = .null,
        createdAt: String? = nil,
        readAt: String? = nil,
        emailedAt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.data = data
        self.createdAt = createdAt
        self.readAt = readAt
        self.emailedAt = emailedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case body
        case data
        case createdAt = "created_at"
        case readAt = "read_at"
        case emailedAt = "emailed_at"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.reqInt(.id)
        kind = box.lString(.kind)
        title = box.lString(.title)
        body = box.lString(.body)
        data = box.lValue(.data)
        createdAt = box.lString(.createdAt)
        readAt = box.lString(.readAt)
        emailedAt = box.lString(.emailedAt)
    }
}

/// `GET /api/notifications`.
public struct NotificationsPage: Codable, Sendable, Hashable {
    public var items: [AppNotification]
    public var total: Int
    public var unread: Int

    public init(items: [AppNotification] = [], total: Int = 0, unread: Int = 0) {
        self.items = items
        self.total = total
        self.unread = unread
    }

    enum CodingKeys: String, CodingKey {
        case items
        case total
        case unread
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        items = box.lAny([AppNotification].self, .items) ?? []
        total = box.lInt(.total) ?? 0
        unread = box.lInt(.unread) ?? 0
    }
}
