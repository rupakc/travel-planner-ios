import Foundation

/// `POST /api/live-check`: no free text, unknown fields are 422.
public struct LiveCheckRequest: Codable, Sendable, Hashable {
    public var kind: WatchKind
    public var watchId: Int

    public init(kind: WatchKind, watchId: Int) {
        self.kind = kind
        self.watchId = watchId
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case watchId = "watch_id"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        kind = try box.reqAny(WatchKind.self, .kind)
        watchId = try box.reqInt(.watchId)
    }
}

public struct LiveQuote: Codable, Sendable, Hashable {
    public var label: String?
    public var amount: Double?
    public var currency: String?
    public var sourceIndex: Int?

    public init(
        label: String? = nil,
        amount: Double? = nil,
        currency: String? = nil,
        sourceIndex: Int? = nil
    ) {
        self.label = label
        self.amount = amount
        self.currency = currency
        self.sourceIndex = sourceIndex
    }

    enum CodingKeys: String, CodingKey {
        case label
        case amount
        case currency
        case sourceIndex = "source_index"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        label = box.lString(.label)
        amount = box.lDouble(.amount)
        currency = box.lString(.currency)
        sourceIndex = box.lInt(.sourceIndex)
    }
}

public struct LiveSource: Codable, Sendable, Hashable {
    public var title: String?
    public var uri: String?

    public init(title: String? = nil, uri: String? = nil) {
        self.title = title
        self.uri = uri
    }

    enum CodingKeys: String, CodingKey {
        case title
        case uri
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        title = box.lString(.title)
        uri = box.lString(.uri)
    }
}

/// Grounded web answer. Google's terms keep it to the requesting user: never store or cache it.
public struct LiveCheckResult: Codable, Sendable, Hashable {
    public var kind: WatchKind?
    public var watchId: Int?
    public var checkedAt: String?
    public var summary: String?
    public var quotes: [LiveQuote]
    public var sources: [LiveSource]
    public var searchedFor: [String]
    public var disclaimer: String?

    public init(
        kind: WatchKind? = nil,
        watchId: Int? = nil,
        checkedAt: String? = nil,
        summary: String? = nil,
        quotes: [LiveQuote] = [],
        sources: [LiveSource] = [],
        searchedFor: [String] = [],
        disclaimer: String? = nil
    ) {
        self.kind = kind
        self.watchId = watchId
        self.checkedAt = checkedAt
        self.summary = summary
        self.quotes = quotes
        self.sources = sources
        self.searchedFor = searchedFor
        self.disclaimer = disclaimer
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case watchId = "watch_id"
        case checkedAt = "checked_at"
        case summary
        case quotes
        case sources
        case searchedFor = "searched_for"
        case disclaimer
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        kind = box.lAny(WatchKind.self, .kind)
        watchId = box.lInt(.watchId)
        checkedAt = box.lString(.checkedAt)
        summary = box.lString(.summary)
        quotes = box.lAny([LiveQuote].self, .quotes) ?? []
        sources = box.lAny([LiveSource].self, .sources) ?? []
        searchedFor = box.lAny([String].self, .searchedFor) ?? []
        disclaimer = box.lString(.disclaimer)
    }
}
