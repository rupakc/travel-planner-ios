import Foundation

public struct ImportImage: Codable, Sendable, Hashable {
    public var mediaType: String
    public var dataBase64: String

    public init(mediaType: String, dataBase64: String) {
        self.mediaType = mediaType
        self.dataBase64 = dataBase64
    }

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case dataBase64 = "data_base64"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        mediaType = try box.reqString(.mediaType)
        dataBase64 = try box.reqString(.dataBase64)
    }
}

/// `POST /api/import/extract`: exactly one of `url`, `text`, `images` (1-4).
public struct LinkImportRequest: Codable, Sendable, Hashable {
    public var url: String?
    public var text: String?
    public var images: [ImportImage]?

    public init(url: String? = nil, text: String? = nil, images: [ImportImage]? = nil) {
        self.url = url
        self.text = text
        self.images = images
    }

    enum CodingKeys: String, CodingKey {
        case url
        case text
        case images
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        url = box.lString(.url)
        text = box.lString(.text)
        images = box.lAny([ImportImage].self, .images)
    }
}

public struct ImportSourceInfo: Codable, Sendable, Hashable {
    public var kind: String?
    public var url: String?
    public var title: String?
    public var siteName: String?
    public var faviconUrl: String?
    public var author: String?

    public init(
        kind: String? = nil,
        url: String? = nil,
        title: String? = nil,
        siteName: String? = nil,
        faviconUrl: String? = nil,
        author: String? = nil
    ) {
        self.kind = kind
        self.url = url
        self.title = title
        self.siteName = siteName
        self.faviconUrl = faviconUrl
        self.author = author
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case url
        case title
        case siteName = "site_name"
        case faviconUrl = "favicon_url"
        case author
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        kind = box.lString(.kind)
        url = box.lString(.url)
        title = box.lString(.title)
        siteName = box.lString(.siteName)
        faviconUrl = box.lString(.faviconUrl)
        author = box.lString(.author)
    }
}

public struct ImportDestination: Codable, Sendable, Hashable {
    public var name: String?
    public var city: String?
    public var country: String?
    public var airports: [String]?
    public var lat: Double?
    public var lng: Double?
    public var placeCount: Int?
    public var nights: Int?

    public init(
        name: String? = nil,
        city: String? = nil,
        country: String? = nil,
        airports: [String]? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        placeCount: Int? = nil,
        nights: Int? = nil
    ) {
        self.name = name
        self.city = city
        self.country = country
        self.airports = airports
        self.lat = lat
        self.lng = lng
        self.placeCount = placeCount
        self.nights = nights
    }

    enum CodingKeys: String, CodingKey {
        case name
        case city
        case country
        case airports
        case lat
        case lng
        case placeCount = "place_count"
        case nights
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = box.lString(.name)
        city = box.lString(.city)
        country = box.lString(.country)
        airports = box.lAny([String].self, .airports)
        lat = box.lDouble(.lat)
        lng = box.lDouble(.lng)
        placeCount = box.lInt(.placeCount)
        nights = box.lInt(.nights)
    }
}

public struct ImportPlace: Codable, Sendable, Hashable {
    public var id: String?
    public var name: String?
    public var kind: String?
    public var city: String?
    public var country: String?
    public var destination: String?
    public var lat: Double?
    public var lng: Double?
    public var approximate: Bool?
    public var verified: Bool?
    public var address: String?
    public var rating: Double?
    public var note: String?
    public var quote: String?
    public var dayHint: Int?
    public var confidence: Double?

    public init(
        id: String? = nil,
        name: String? = nil,
        kind: String? = nil,
        city: String? = nil,
        country: String? = nil,
        destination: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        approximate: Bool? = nil,
        verified: Bool? = nil,
        address: String? = nil,
        rating: Double? = nil,
        note: String? = nil,
        quote: String? = nil,
        dayHint: Int? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.city = city
        self.country = country
        self.destination = destination
        self.lat = lat
        self.lng = lng
        self.approximate = approximate
        self.verified = verified
        self.address = address
        self.rating = rating
        self.note = note
        self.quote = quote
        self.dayHint = dayHint
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case city
        case country
        case destination
        case lat
        case lng
        case approximate
        case verified
        case address
        case rating
        case note
        case quote
        case dayHint = "day_hint"
        case confidence
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = box.lString(.id)
        name = box.lString(.name)
        kind = box.lString(.kind)
        city = box.lString(.city)
        country = box.lString(.country)
        destination = box.lString(.destination)
        lat = box.lDouble(.lat)
        lng = box.lDouble(.lng)
        approximate = box.lBool(.approximate)
        verified = box.lBool(.verified)
        address = box.lString(.address)
        rating = box.lDouble(.rating)
        note = box.lString(.note)
        quote = box.lString(.quote)
        dayHint = box.lInt(.dayHint)
        confidence = box.lDouble(.confidence)
    }
}

/// The import preview the traveller reviews.
public struct LinkImportResult: Codable, Sendable, Hashable {
    public var source: ImportSourceInfo?
    public var title: String?
    public var summary: String?
    public var destinations: [ImportDestination]
    public var places: [ImportPlace]
    public var unresolved: [ImportPlace]
    public var alsoMentioned: [JSONValue]
    public var suggestedDays: Int?
    public var seasonHint: String?
    public var interests: [String]
    public var warnings: [String]

    public init(
        source: ImportSourceInfo? = nil,
        title: String? = nil,
        summary: String? = nil,
        destinations: [ImportDestination] = [],
        places: [ImportPlace] = [],
        unresolved: [ImportPlace] = [],
        alsoMentioned: [JSONValue] = [],
        suggestedDays: Int? = nil,
        seasonHint: String? = nil,
        interests: [String] = [],
        warnings: [String] = []
    ) {
        self.source = source
        self.title = title
        self.summary = summary
        self.destinations = destinations
        self.places = places
        self.unresolved = unresolved
        self.alsoMentioned = alsoMentioned
        self.suggestedDays = suggestedDays
        self.seasonHint = seasonHint
        self.interests = interests
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case source
        case title
        case summary
        case destinations
        case places
        case unresolved
        case alsoMentioned = "also_mentioned"
        case suggestedDays = "suggested_days"
        case seasonHint = "season_hint"
        case interests
        case warnings
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        source = box.lAny(ImportSourceInfo.self, .source)
        title = box.lString(.title)
        summary = box.lString(.summary)
        destinations = box.lAny([ImportDestination].self, .destinations) ?? []
        places = box.lAny([ImportPlace].self, .places) ?? []
        unresolved = box.lAny([ImportPlace].self, .unresolved) ?? []
        alsoMentioned = box.lAny([JSONValue].self, .alsoMentioned) ?? []
        suggestedDays = box.lInt(.suggestedDays)
        seasonHint = box.lString(.seasonHint)
        interests = box.lAny([String].self, .interests) ?? []
        warnings = box.lAny([String].self, .warnings) ?? []
    }
}

/// `POST /api/import/resolve-place`.
public struct ResolvePlaceRequest: Codable, Sendable, Hashable {
    public var id: String?
    public var name: String
    public var kind: String?
    public var city: String
    public var country: String?
    public var note: String?
    public var quote: String?

    public init(
        id: String? = nil,
        name: String,
        kind: String? = nil,
        city: String,
        country: String? = nil,
        note: String? = nil,
        quote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.city = city
        self.country = country
        self.note = note
        self.quote = quote
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case city
        case country
        case note
        case quote
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = box.lString(.id)
        name = try box.reqString(.name)
        kind = box.lString(.kind)
        city = try box.reqString(.city)
        country = box.lString(.country)
        note = box.lString(.note)
        quote = box.lString(.quote)
    }
}
