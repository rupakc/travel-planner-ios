import Foundation

/// `GET/PUT /api/preferences`. PUT replaces every field: omitted ones reset to the server default.
public struct Preferences: Codable, Sendable, Hashable {
    public var username: String?
    public var budgetCategory: String?
    public var nationality: String?
    public var currentResidence: String?
    public var residencePermits: [String]?
    public var existingVisas: [String]?
    public var interests: [String]?
    public var numTravelers: Int?
    public var adults: Int?
    public var children: Int?
    public var seniors: Int?
    public var infants: Int?
    public var accessibilityNeeds: [String]?
    public var updatedAt: String?

    public init(
        username: String? = nil,
        budgetCategory: String? = nil,
        nationality: String? = nil,
        currentResidence: String? = nil,
        residencePermits: [String]? = nil,
        existingVisas: [String]? = nil,
        interests: [String]? = nil,
        numTravelers: Int? = nil,
        adults: Int? = nil,
        children: Int? = nil,
        seniors: Int? = nil,
        infants: Int? = nil,
        accessibilityNeeds: [String]? = nil,
        updatedAt: String? = nil
    ) {
        self.username = username
        self.budgetCategory = budgetCategory
        self.nationality = nationality
        self.currentResidence = currentResidence
        self.residencePermits = residencePermits
        self.existingVisas = existingVisas
        self.interests = interests
        self.numTravelers = numTravelers
        self.adults = adults
        self.children = children
        self.seniors = seniors
        self.infants = infants
        self.accessibilityNeeds = accessibilityNeeds
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case username
        case budgetCategory = "budget_category"
        case nationality
        case currentResidence = "current_residence"
        case residencePermits = "residence_permits"
        case existingVisas = "existing_visas"
        case interests
        case numTravelers = "num_travelers"
        case adults
        case children
        case seniors
        case infants
        case accessibilityNeeds = "accessibility_needs"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        username = box.lString(.username)
        budgetCategory = box.lString(.budgetCategory)
        nationality = box.lString(.nationality)
        currentResidence = box.lString(.currentResidence)
        residencePermits = box.lAny([String].self, .residencePermits)
        existingVisas = box.lAny([String].self, .existingVisas)
        interests = box.lAny([String].self, .interests)
        numTravelers = box.lInt(.numTravelers)
        adults = box.lInt(.adults)
        children = box.lInt(.children)
        seniors = box.lInt(.seniors)
        infants = box.lInt(.infants)
        accessibilityNeeds = box.lAny([String].self, .accessibilityNeeds)
        updatedAt = box.lString(.updatedAt)
    }
}

public struct TasteSignal: Codable, Sendable, Hashable {
    public var value: String?
    public var count: Int?

    public init(value: String? = nil, count: Int? = nil) {
        self.value = value
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case value
        case count
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        value = box.lString(.value)
        count = box.lInt(.count)
    }
}

/// `GET /api/taste-profile`.
public struct TasteProfile: Codable, Sendable, Hashable {
    public var signals: [String: [TasteSignal]]?
    public var totalSignals: Int?
    public var context: String?

    public init(signals: [String: [TasteSignal]]? = nil, totalSignals: Int? = nil, context: String? = nil) {
        self.signals = signals
        self.totalSignals = totalSignals
        self.context = context
    }

    enum CodingKeys: String, CodingKey {
        case signals
        case totalSignals = "total_signals"
        case context
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        signals = box.lAny([String: [TasteSignal]].self, .signals)
        totalSignals = box.lInt(.totalSignals)
        context = box.lString(.context)
    }
}

/// A row of `GET /api/airports/search`.
public struct AirportSuggestion: Codable, Sendable, Hashable {
    public var iataCode: String?
    public var name: String?
    public var city: String?
    public var country: String?
    public var countryCode: String?

    public init(
        iataCode: String? = nil,
        name: String? = nil,
        city: String? = nil,
        country: String? = nil,
        countryCode: String? = nil
    ) {
        self.iataCode = iataCode
        self.name = name
        self.city = city
        self.country = country
        self.countryCode = countryCode
    }

    enum CodingKeys: String, CodingKey {
        case iataCode = "iata_code"
        case name
        case city
        case country
        case countryCode = "country_code"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        iataCode = box.lString(.iataCode)
        name = box.lString(.name)
        city = box.lString(.city)
        country = box.lString(.country)
        countryCode = box.lString(.countryCode)
    }
}

/// A row of `GET /api/nationalities/search`.
public struct NationalitySuggestion: Codable, Sendable, Hashable {
    public var nationality: String?
    public var country: String?
    public var countryCode: String?

    public init(nationality: String? = nil, country: String? = nil, countryCode: String? = nil) {
        self.nationality = nationality
        self.country = country
        self.countryCode = countryCode
    }

    enum CodingKeys: String, CodingKey {
        case nationality
        case country
        case countryCode = "country_code"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        nationality = box.lString(.nationality)
        country = box.lString(.country)
        countryCode = box.lString(.countryCode)
    }
}
