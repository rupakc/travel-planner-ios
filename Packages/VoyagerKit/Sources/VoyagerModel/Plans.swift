import Foundation

/// A saved plan as listed by `GET /api/plans` (selections are left to `SavedPlan`).
public struct PlanSummary: Codable, Sendable, Hashable {
    public var id: Int
    public var name: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var shareToken: String?
    public var searchData: JSONValue

    public init(
        id: Int,
        name: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        shareToken: String? = nil,
        searchData: JSONValue = .null
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.shareToken = shareToken
        self.searchData = searchData
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case shareToken = "share_token"
        case searchData = "search_data"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.reqInt(.id)
        name = box.lString(.name)
        createdAt = box.lString(.createdAt)
        updatedAt = box.lString(.updatedAt)
        shareToken = box.lString(.shareToken)
        searchData = box.lValue(.searchData)
    }
}

/// A saved plan (`GET/POST/PUT /api/plans`). Timestamps are SQLite UTC strings.
public struct SavedPlan: Codable, Sendable, Hashable {
    public var id: Int
    public var name: String
    public var searchData: JSONValue
    public var selections: JSONValue
    public var createdAt: String?
    public var updatedAt: String?
    public var shareToken: String?

    public init(
        id: Int,
        name: String,
        searchData: JSONValue = .null,
        selections: JSONValue = .null,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        shareToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.searchData = searchData
        self.selections = selections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.shareToken = shareToken
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case searchData = "search_data"
        case selections
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case shareToken = "share_token"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.reqInt(.id)
        name = try box.reqString(.name)
        searchData = box.lValue(.searchData)
        selections = box.lValue(.selections)
        createdAt = box.lString(.createdAt)
        updatedAt = box.lString(.updatedAt)
        shareToken = box.lString(.shareToken)
    }
}

/// `POST /api/plans` body (all three required).
public struct NewPlan: Codable, Sendable, Hashable {
    public var name: String
    public var searchData: JSONValue
    public var selections: JSONValue

    public init(name: String, searchData: JSONValue = .object([:]), selections: JSONValue = .object([:])) {
        self.name = name
        self.searchData = searchData
        self.selections = selections
    }

    enum CodingKeys: String, CodingKey {
        case name
        case searchData = "search_data"
        case selections
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = try box.reqString(.name)
        searchData = box.lValue(.searchData).object == nil ? .object([:]) : box.lValue(.searchData)
        selections = box.lValue(.selections).object == nil ? .object([:]) : box.lValue(.selections)
    }
}

/// `PUT /api/plans/{id}` body (`search_data` is immutable after create).
public struct PlanUpdate: Codable, Sendable, Hashable {
    public var name: String?
    public var selections: JSONValue?

    public init(name: String? = nil, selections: JSONValue? = nil) {
        self.name = name
        self.selections = selections
    }

    enum CodingKeys: String, CodingKey {
        case name
        case selections
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = box.lString(.name)
        selections = box.lAny(JSONValue.self, .selections)
    }
}

/// A recap or savings share's card (Sharing API, Phase 4): counts only, never dates.
public struct SharedCard: Codable, Sendable, Hashable {
    public struct Stat: Codable, Sendable, Hashable {
        public var key: String
        public var count: Int

        public init(key: String, count: Int) {
            self.key = key
            self.count = count
        }
    }

    public var headline: String?
    public var stats: [Stat]
    public var destination: String?
    public var period: String?

    public init(headline: String? = nil, stats: [Stat] = [], destination: String? = nil, period: String? = nil) {
        self.headline = headline
        self.stats = stats
        self.destination = destination
        self.period = period
    }

    enum CodingKeys: String, CodingKey { case headline, stats, destination, period }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        headline = box.lString(.headline)
        stats = box.lAny([Stat].self, .stats) ?? []
        destination = box.lString(.destination)
        period = box.lString(.period)
    }
}

/// `GET /api/share/{token}`: public, personal fields already stripped by the server. A Phase 4 token adds
/// `kind`, `owner_name` (only with the sharer's "show my name") and, for recap and savings, `card`;
/// a legacy token has none of them.
public struct SharedPlan: Codable, Sendable, Hashable {
    public var name: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var searchData: JSONValue
    public var selections: JSONValue
    public var kind: String?
    public var ownerName: String?
    public var card: SharedCard?

    public init(
        name: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        searchData: JSONValue = .null,
        selections: JSONValue = .null,
        kind: String? = nil,
        ownerName: String? = nil,
        card: SharedCard? = nil
    ) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.searchData = searchData
        self.selections = selections
        self.kind = kind
        self.ownerName = ownerName
        self.card = card
    }

    enum CodingKeys: String, CodingKey {
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case searchData = "search_data"
        case selections
        case kind
        case ownerName = "owner_name"
        case card
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = box.lString(.name)
        createdAt = box.lString(.createdAt)
        updatedAt = box.lString(.updatedAt)
        searchData = box.lValue(.searchData)
        selections = box.lValue(.selections)
        kind = box.lString(.kind)
        ownerName = box.lString(.ownerName)
        card = box.lAny(SharedCard.self, .card)
    }
}
