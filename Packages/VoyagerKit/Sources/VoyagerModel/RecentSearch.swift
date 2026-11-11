import Foundation

/// A row of `GET /api/recent-searches` (the Search form as submitted).
public struct RecentSearch: Codable, Sendable, Hashable {
    public var id: Int
    public var search: JSONValue
    public var lastUsedAt: String?

    public init(id: Int, search: JSONValue = .null, lastUsedAt: String? = nil) {
        self.id = id
        self.search = search
        self.lastUsedAt = lastUsedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case search
        case lastUsedAt = "last_used_at"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.reqInt(.id)
        search = box.lValue(.search)
        lastUsedAt = box.lString(.lastUsedAt)
    }
}
