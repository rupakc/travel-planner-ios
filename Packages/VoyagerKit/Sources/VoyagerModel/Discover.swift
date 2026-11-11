import Foundation

/// `POST /api/discover` ("Surprise me").
public struct DiscoverRequest: Codable, Sendable, Hashable {
    public var origin: String?
    public var nationality: String?
    public var departureDate: String?
    public var returnDate: String?
    public var budgetUsd: Double?
    public var interests: [String]?
    public var adults: Int?
    public var children: Int?
    public var seniors: Int?
    public var infants: Int?
    public var locale: AppLanguage?

    public init(
        origin: String? = nil,
        nationality: String? = nil,
        departureDate: String? = nil,
        returnDate: String? = nil,
        budgetUsd: Double? = nil,
        interests: [String]? = nil,
        adults: Int? = nil,
        children: Int? = nil,
        seniors: Int? = nil,
        infants: Int? = nil,
        locale: AppLanguage? = nil
    ) {
        self.origin = origin
        self.nationality = nationality
        self.departureDate = departureDate
        self.returnDate = returnDate
        self.budgetUsd = budgetUsd
        self.interests = interests
        self.adults = adults
        self.children = children
        self.seniors = seniors
        self.infants = infants
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case origin
        case nationality
        case departureDate = "departure_date"
        case returnDate = "return_date"
        case budgetUsd = "budget_usd"
        case interests
        case adults
        case children
        case seniors
        case infants
        case locale
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        origin = box.lString(.origin)
        nationality = box.lString(.nationality)
        departureDate = box.lString(.departureDate)
        returnDate = box.lString(.returnDate)
        budgetUsd = box.lDouble(.budgetUsd)
        interests = box.lAny([String].self, .interests)
        adults = box.lInt(.adults)
        children = box.lInt(.children)
        seniors = box.lInt(.seniors)
        infants = box.lInt(.infants)
        locale = box.lAny(AppLanguage.self, .locale)
    }
}

public struct DiscoverSuggestion: Codable, Sendable, Hashable {
    public var city: String?
    public var country: String?
    public var estimatedCostUsdLow: Double?
    public var estimatedCostUsdHigh: Double?
    public var visaType: String?
    public var visaVerified: Bool?
    public var weatherEmoji: String?
    public var weatherDescription: String?
    public var flightDurationHours: Double?
    public var flightDurationLabel: String?
    public var matchReasons: [String]?
    public var highlights: [String]?

    public init(
        city: String? = nil,
        country: String? = nil,
        estimatedCostUsdLow: Double? = nil,
        estimatedCostUsdHigh: Double? = nil,
        visaType: String? = nil,
        visaVerified: Bool? = nil,
        weatherEmoji: String? = nil,
        weatherDescription: String? = nil,
        flightDurationHours: Double? = nil,
        flightDurationLabel: String? = nil,
        matchReasons: [String]? = nil,
        highlights: [String]? = nil
    ) {
        self.city = city
        self.country = country
        self.estimatedCostUsdLow = estimatedCostUsdLow
        self.estimatedCostUsdHigh = estimatedCostUsdHigh
        self.visaType = visaType
        self.visaVerified = visaVerified
        self.weatherEmoji = weatherEmoji
        self.weatherDescription = weatherDescription
        self.flightDurationHours = flightDurationHours
        self.flightDurationLabel = flightDurationLabel
        self.matchReasons = matchReasons
        self.highlights = highlights
    }

    enum CodingKeys: String, CodingKey {
        case city
        case country
        case estimatedCostUsdLow = "estimated_cost_usd_low"
        case estimatedCostUsdHigh = "estimated_cost_usd_high"
        case visaType = "visa_type"
        case visaVerified = "visa_verified"
        case weatherEmoji = "weather_emoji"
        case weatherDescription = "weather_description"
        case flightDurationHours = "flight_duration_hours"
        case flightDurationLabel = "flight_duration_label"
        case matchReasons = "match_reasons"
        case highlights
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        city = box.lString(.city)
        country = box.lString(.country)
        estimatedCostUsdLow = box.lDouble(.estimatedCostUsdLow)
        estimatedCostUsdHigh = box.lDouble(.estimatedCostUsdHigh)
        visaType = box.lString(.visaType)
        visaVerified = box.lBool(.visaVerified)
        weatherEmoji = box.lString(.weatherEmoji)
        weatherDescription = box.lString(.weatherDescription)
        flightDurationHours = box.lDouble(.flightDurationHours)
        flightDurationLabel = box.lString(.flightDurationLabel)
        matchReasons = box.lAny([String].self, .matchReasons)
        highlights = box.lAny([String].self, .highlights)
    }
}

public struct DiscoverResponse: Codable, Sendable, Hashable {
    public var destinations: [DiscoverSuggestion]

    public init(destinations: [DiscoverSuggestion] = []) {
        self.destinations = destinations
    }

    enum CodingKeys: String, CodingKey {
        case destinations
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        destinations = box.lAny([DiscoverSuggestion].self, .destinations) ?? []
    }
}
