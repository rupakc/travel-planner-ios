import Foundation

/// The four Near me v2 groups, always in the order see, eat, shop, stay (any may be empty).
public typealias NearbySections = [NearbySection]

/// `POST /api/nearby`. `sections: true` asks for Near me v2 (Google Maps grounded).
public struct NearbyRequest: Codable, Sendable, Hashable {
    public var lat: Double
    public var lng: Double
    public var interests: [String]?
    public var limit: Int?
    public var sections: Bool?
    public var language: String?

    public init(
        lat: Double,
        lng: Double,
        interests: [String]? = nil,
        limit: Int? = nil,
        sections: Bool? = nil,
        language: String? = nil
    ) {
        self.lat = lat
        self.lng = lng
        self.interests = interests
        self.limit = limit
        self.sections = sections
        self.language = language
    }

    enum CodingKeys: String, CodingKey {
        case lat
        case lng
        case interests
        case limit
        case sections
        case language
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        lat = try box.reqDouble(.lat)
        lng = try box.reqDouble(.lng)
        interests = box.lAny([String].self, .interests)
        limit = box.lInt(.limit)
        sections = box.lBool(.sections)
        language = box.lString(.language)
    }
}

public struct NearbyPlace: Codable, Sendable, Hashable {
    public var name: String?
    public var region: String?
    public var country: String?
    public var countryCode: String?
    public var lat: Double?
    public var lng: Double?
    public var distanceKm: Double?

    public init(
        name: String? = nil,
        region: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        distanceKm: Double? = nil
    ) {
        self.name = name
        self.region = region
        self.country = country
        self.countryCode = countryCode
        self.lat = lat
        self.lng = lng
        self.distanceKm = distanceKm
    }

    enum CodingKeys: String, CodingKey {
        case name
        case region
        case country
        case countryCode = "country_code"
        case lat
        case lng
        case distanceKm = "distance_km"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = box.lString(.name)
        region = box.lString(.region)
        country = box.lString(.country)
        countryCode = box.lString(.countryCode)
        lat = box.lDouble(.lat)
        lng = box.lDouble(.lng)
        distanceKm = box.lDouble(.distanceKm)
    }
}

public struct NearbyItem: Codable, Sendable, Hashable {
    public var name: String?
    public var summary: String?
    public var mapsUri: String?
    public var placeId: String?
    public var category: String?

    public init(
        name: String? = nil,
        summary: String? = nil,
        mapsUri: String? = nil,
        placeId: String? = nil,
        category: String? = nil
    ) {
        self.name = name
        self.summary = summary
        self.mapsUri = mapsUri
        self.placeId = placeId
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case name
        case summary
        case mapsUri = "maps_uri"
        case placeId = "place_id"
        case category
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        name = box.lString(.name)
        summary = box.lString(.summary)
        mapsUri = box.lString(.mapsUri)
        placeId = box.lString(.placeId)
        category = box.lString(.category)
    }
}

public struct NearbySection: Codable, Sendable, Hashable {
    public var id: String?
    public var title: String?
    public var items: [NearbyItem]

    public init(id: String? = nil, title: String? = nil, items: [NearbyItem] = []) {
        self.id = id
        self.title = title
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case items
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = box.lString(.id)
        title = box.lString(.title)
        items = box.lAny([NearbyItem].self, .items) ?? []
    }
}

public struct NearbySource: Codable, Sendable, Hashable {
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

/// v1 answers `items` (activities-agent results, unchanged); v2 answers `sections`, `attribution` and `sources`.
public struct NearbyResponse: Codable, Sendable, Hashable {
    public var place: NearbyPlace?
    public var items: [JSONValue]?
    public var sections: NearbySections?
    public var attribution: String?
    public var sources: [NearbySource]?

    public init(
        place: NearbyPlace? = nil,
        items: [JSONValue]? = nil,
        sections: NearbySections? = nil,
        attribution: String? = nil,
        sources: [NearbySource]? = nil
    ) {
        self.place = place
        self.items = items
        self.sections = sections
        self.attribution = attribution
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case place
        case items
        case sections
        case attribution
        case sources
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        place = box.lAny(NearbyPlace.self, .place)
        items = box.lAny([JSONValue].self, .items)
        sections = box.lAny(NearbySections.self, .sections)
        attribution = box.lString(.attribution)
        sources = box.lAny([NearbySource].self, .sources)
    }
}
