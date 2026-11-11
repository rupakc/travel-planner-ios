import Foundation

public struct CompareFlight: Codable, Sendable, Hashable {
    public var priceUsd: Double?
    public var stops: Int?
    public var durationMinutes: Int?
    public var airline: String?
    public var source: String?

    public init(
        priceUsd: Double? = nil,
        stops: Int? = nil,
        durationMinutes: Int? = nil,
        airline: String? = nil,
        source: String? = nil
    ) {
        self.priceUsd = priceUsd
        self.stops = stops
        self.durationMinutes = durationMinutes
        self.airline = airline
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case priceUsd = "price_usd"
        case stops
        case durationMinutes = "duration_minutes"
        case airline
        case source
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        priceUsd = box.lDouble(.priceUsd)
        stops = box.lInt(.stops)
        durationMinutes = box.lInt(.durationMinutes)
        airline = box.lString(.airline)
        source = box.lString(.source)
    }
}

public struct CompareHotel: Codable, Sendable, Hashable {
    public var typicalNightlyUsd: Double?
    public var cheapestGoodNightlyUsd: Double?
    public var count: Int?

    public init(
        typicalNightlyUsd: Double? = nil,
        cheapestGoodNightlyUsd: Double? = nil,
        count: Int? = nil
    ) {
        self.typicalNightlyUsd = typicalNightlyUsd
        self.cheapestGoodNightlyUsd = cheapestGoodNightlyUsd
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case typicalNightlyUsd = "typical_nightly_usd"
        case cheapestGoodNightlyUsd = "cheapest_good_nightly_usd"
        case count
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        typicalNightlyUsd = box.lDouble(.typicalNightlyUsd)
        cheapestGoodNightlyUsd = box.lDouble(.cheapestGoodNightlyUsd)
        count = box.lInt(.count)
    }
}

public struct CompareWeather: Codable, Sendable, Hashable {
    public var avgHighC: Double?
    public var avgLowC: Double?
    public var poorDays: Int?
    public var totalDays: Int?
    public var source: String?

    public init(
        avgHighC: Double? = nil,
        avgLowC: Double? = nil,
        poorDays: Int? = nil,
        totalDays: Int? = nil,
        source: String? = nil
    ) {
        self.avgHighC = avgHighC
        self.avgLowC = avgLowC
        self.poorDays = poorDays
        self.totalDays = totalDays
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case avgHighC = "avg_high_c"
        case avgLowC = "avg_low_c"
        case poorDays = "poor_days"
        case totalDays = "total_days"
        case source
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        avgHighC = box.lDouble(.avgHighC)
        avgLowC = box.lDouble(.avgLowC)
        poorDays = box.lInt(.poorDays)
        totalDays = box.lInt(.totalDays)
        source = box.lString(.source)
    }
}

public struct CompareVisa: Codable, Sendable, Hashable {
    public var visaType: String?
    public var maxStayDays: Int?
    public var feeUsd: Double?
    public var processingTime: String?
    public var verified: Bool?

    public init(
        visaType: String? = nil,
        maxStayDays: Int? = nil,
        feeUsd: Double? = nil,
        processingTime: String? = nil,
        verified: Bool? = nil
    ) {
        self.visaType = visaType
        self.maxStayDays = maxStayDays
        self.feeUsd = feeUsd
        self.processingTime = processingTime
        self.verified = verified
    }

    enum CodingKeys: String, CodingKey {
        case visaType = "visa_type"
        case maxStayDays = "max_stay_days"
        case feeUsd = "fee_usd"
        case processingTime = "processing_time"
        case verified
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        visaType = box.lString(.visaType)
        maxStayDays = box.lInt(.maxStayDays)
        feeUsd = box.lDouble(.feeUsd)
        processingTime = box.lString(.processingTime)
        verified = box.lBool(.verified)
    }
}

public struct CompareEase: Codable, Sendable, Hashable {
    public var total: Int?
    public var grade: String?
    public var safety: Int?
    public var english: Int?
    public var infrastructure: Int?
    public var visaEase: Int?

    public init(
        total: Int? = nil,
        grade: String? = nil,
        safety: Int? = nil,
        english: Int? = nil,
        infrastructure: Int? = nil,
        visaEase: Int? = nil
    ) {
        self.total = total
        self.grade = grade
        self.safety = safety
        self.english = english
        self.infrastructure = infrastructure
        self.visaEase = visaEase
    }

    enum CodingKeys: String, CodingKey {
        case total
        case grade
        case safety
        case english
        case infrastructure
        case visaEase = "visa_ease"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        total = box.lInt(.total)
        grade = box.lString(.grade)
        safety = box.lInt(.safety)
        english = box.lInt(.english)
        infrastructure = box.lInt(.infrastructure)
        visaEase = box.lInt(.visaEase)
    }
}

public struct CompareEstimate: Codable, Sendable, Hashable {
    public var totalUsd: Double?
    public var flightUsd: Double?
    public var stayUsd: Double?
    public var dailyUsd: Double?
    public var includedInDaily: Bool?
    public var nights: Int?
    public var partial: Bool?
    public var budgetStatus: String?

    public init(
        totalUsd: Double? = nil,
        flightUsd: Double? = nil,
        stayUsd: Double? = nil,
        dailyUsd: Double? = nil,
        includedInDaily: Bool? = nil,
        nights: Int? = nil,
        partial: Bool? = nil,
        budgetStatus: String? = nil
    ) {
        self.totalUsd = totalUsd
        self.flightUsd = flightUsd
        self.stayUsd = stayUsd
        self.dailyUsd = dailyUsd
        self.includedInDaily = includedInDaily
        self.nights = nights
        self.partial = partial
        self.budgetStatus = budgetStatus
    }

    enum CodingKeys: String, CodingKey {
        case totalUsd = "total_usd"
        case flightUsd = "flight_usd"
        case stayUsd = "stay_usd"
        case dailyUsd = "daily_usd"
        case includedInDaily = "included_in_daily"
        case nights
        case partial
        case budgetStatus = "budget_status"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        totalUsd = box.lDouble(.totalUsd)
        flightUsd = box.lDouble(.flightUsd)
        stayUsd = box.lDouble(.stayUsd)
        dailyUsd = box.lDouble(.dailyUsd)
        includedInDaily = box.lBool(.includedInDaily)
        nights = box.lInt(.nights)
        partial = box.lBool(.partial)
        budgetStatus = box.lString(.budgetStatus)
    }
}

/// `POST /api/compare/destination`: one destination's summary. A missing piece is nil and listed in `missing`.
public struct CompareSummary: Codable, Sendable, Hashable {
    public var destination: String?
    public var label: String?
    public var flight: CompareFlight?
    public var hotel: CompareHotel?
    public var weather: CompareWeather?
    public var visa: CompareVisa?
    public var ease: CompareEase?
    public var dailyCostUsd: Double?
    public var estimate: CompareEstimate?
    public var missing: [String]

    public init(
        destination: String? = nil,
        label: String? = nil,
        flight: CompareFlight? = nil,
        hotel: CompareHotel? = nil,
        weather: CompareWeather? = nil,
        visa: CompareVisa? = nil,
        ease: CompareEase? = nil,
        dailyCostUsd: Double? = nil,
        estimate: CompareEstimate? = nil,
        missing: [String] = []
    ) {
        self.destination = destination
        self.label = label
        self.flight = flight
        self.hotel = hotel
        self.weather = weather
        self.visa = visa
        self.ease = ease
        self.dailyCostUsd = dailyCostUsd
        self.estimate = estimate
        self.missing = missing
    }

    enum CodingKeys: String, CodingKey {
        case destination
        case label
        case flight
        case hotel
        case weather
        case visa
        case ease
        case dailyCostUsd = "daily_cost_usd"
        case estimate
        case missing
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        destination = box.lString(.destination)
        label = box.lString(.label)
        flight = box.lAny(CompareFlight.self, .flight)
        hotel = box.lAny(CompareHotel.self, .hotel)
        weather = box.lAny(CompareWeather.self, .weather)
        visa = box.lAny(CompareVisa.self, .visa)
        ease = box.lAny(CompareEase.self, .ease)
        dailyCostUsd = box.lDouble(.dailyCostUsd)
        estimate = box.lAny(CompareEstimate.self, .estimate)
        missing = box.lAny([String].self, .missing) ?? []
    }
}
