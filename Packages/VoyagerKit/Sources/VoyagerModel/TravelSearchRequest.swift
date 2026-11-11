import Foundation

/// The body of `POST /api/search` and of every single-agent route (API-Reference
/// `TravelSearchRequest`). Dates are `YYYY-MM-DD` strings. Nil fields are omitted on encode.
public struct TravelSearchRequest: Codable, Sendable, Hashable {
    public var origin: String?
    public var destination: String?
    public var departureDate: String?
    public var returnDate: String?
    public var nationality: String?
    public var interests: [String]?
    public var budgetUsd: Double?
    public var numTravelers: Int?
    public var adults: Int?
    public var children: Int?
    public var seniors: Int?
    public var infants: Int?
    public var accessibilityNeeds: [String]?
    public var residencePermits: [String]?
    public var existingVisas: [String]?
    public var destinations: [String]?
    public var destinationNights: [Int]?
    public var pace: String?
    public var serendipity: Double?
    public var locale: AppLanguage?
    public var mustInclude: [JSONValue]?
    public var importSource: JSONValue?

    public init(
        origin: String? = nil,
        destination: String? = nil,
        departureDate: String? = nil,
        returnDate: String? = nil,
        nationality: String? = nil,
        interests: [String]? = nil,
        budgetUsd: Double? = nil,
        numTravelers: Int? = nil,
        adults: Int? = nil,
        children: Int? = nil,
        seniors: Int? = nil,
        infants: Int? = nil,
        accessibilityNeeds: [String]? = nil,
        residencePermits: [String]? = nil,
        existingVisas: [String]? = nil,
        destinations: [String]? = nil,
        destinationNights: [Int]? = nil,
        pace: String? = nil,
        serendipity: Double? = nil,
        locale: AppLanguage? = nil,
        mustInclude: [JSONValue]? = nil,
        importSource: JSONValue? = nil
    ) {
        self.origin = origin
        self.destination = destination
        self.departureDate = departureDate
        self.returnDate = returnDate
        self.nationality = nationality
        self.interests = interests
        self.budgetUsd = budgetUsd
        self.numTravelers = numTravelers
        self.adults = adults
        self.children = children
        self.seniors = seniors
        self.infants = infants
        self.accessibilityNeeds = accessibilityNeeds
        self.residencePermits = residencePermits
        self.existingVisas = existingVisas
        self.destinations = destinations
        self.destinationNights = destinationNights
        self.pace = pace
        self.serendipity = serendipity
        self.locale = locale
        self.mustInclude = mustInclude
        self.importSource = importSource
    }

    enum CodingKeys: String, CodingKey {
        case origin
        case destination
        case departureDate = "departure_date"
        case returnDate = "return_date"
        case nationality
        case interests
        case budgetUsd = "budget_usd"
        case numTravelers = "num_travelers"
        case adults
        case children
        case seniors
        case infants
        case accessibilityNeeds = "accessibility_needs"
        case residencePermits = "residence_permits"
        case existingVisas = "existing_visas"
        case destinations
        case destinationNights = "destination_nights"
        case pace
        case serendipity
        case locale
        case mustInclude = "must_include"
        case importSource = "import_source"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        origin = box.lString(.origin)
        destination = box.lString(.destination)
        departureDate = box.lString(.departureDate)
        returnDate = box.lString(.returnDate)
        nationality = box.lString(.nationality)
        interests = box.lAny([String].self, .interests)
        budgetUsd = box.lDouble(.budgetUsd)
        numTravelers = box.lInt(.numTravelers)
        adults = box.lInt(.adults)
        children = box.lInt(.children)
        seniors = box.lInt(.seniors)
        infants = box.lInt(.infants)
        accessibilityNeeds = box.lAny([String].self, .accessibilityNeeds)
        residencePermits = box.lAny([String].self, .residencePermits)
        existingVisas = box.lAny([String].self, .existingVisas)
        destinations = box.lAny([String].self, .destinations)
        destinationNights = box.lAny([Int].self, .destinationNights)
        pace = box.lString(.pace)
        serendipity = box.lDouble(.serendipity)
        locale = box.lAny(AppLanguage.self, .locale)
        mustInclude = box.lAny([JSONValue].self, .mustInclude)
        importSource = box.lAny(JSONValue.self, .importSource)
    }
}
