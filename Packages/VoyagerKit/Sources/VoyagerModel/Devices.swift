import Foundation

/// A registered push device; the server masks the token to its last 6 characters.
public struct Device: Codable, Sendable, Hashable {
    public var id: Int
    public var token: String?
    public var platform: String?
    public var locale: String?
    public var createdAt: String?
    public var lastSeenAt: String?

    public init(
        id: Int,
        token: String? = nil,
        platform: String? = nil,
        locale: String? = nil,
        createdAt: String? = nil,
        lastSeenAt: String? = nil
    ) {
        self.id = id
        self.token = token
        self.platform = platform
        self.locale = locale
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case token
        case platform
        case locale
        case createdAt = "created_at"
        case lastSeenAt = "last_seen_at"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.reqInt(.id)
        token = box.lString(.token)
        platform = box.lString(.platform)
        locale = box.lString(.locale)
        createdAt = box.lString(.createdAt)
        lastSeenAt = box.lString(.lastSeenAt)
    }
}

/// `POST /api/devices` body. The token only ever travels in a body.
public struct DeviceRegistration: Codable, Sendable, Hashable {
    public var token: String
    public var platform: String
    public var locale: String?

    public init(token: String, platform: String, locale: String? = nil) {
        self.token = token
        self.platform = platform
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case token
        case platform
        case locale
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        token = try box.reqString(.token)
        platform = try box.reqString(.platform)
        locale = box.lString(.locale)
    }
}
