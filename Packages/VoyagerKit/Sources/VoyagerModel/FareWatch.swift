import Foundation

public struct FareWatchHistoryPoint: Codable, Sendable, Hashable {
    public var checkedAt: String?
    public var price: Double?
    public var cheapestPrice: Double?
    public var cheapestDepartureDate: String?
    public var cheapestReturnDate: String?
    public var priceLevel: String?

    public init(
        checkedAt: String? = nil,
        price: Double? = nil,
        cheapestPrice: Double? = nil,
        cheapestDepartureDate: String? = nil,
        cheapestReturnDate: String? = nil,
        priceLevel: String? = nil
    ) {
        self.checkedAt = checkedAt
        self.price = price
        self.cheapestPrice = cheapestPrice
        self.cheapestDepartureDate = cheapestDepartureDate
        self.cheapestReturnDate = cheapestReturnDate
        self.priceLevel = priceLevel
    }

    enum CodingKeys: String, CodingKey {
        case checkedAt = "checked_at"
        case price
        case cheapestPrice = "cheapest_price"
        case cheapestDepartureDate = "cheapest_departure_date"
        case cheapestReturnDate = "cheapest_return_date"
        case priceLevel = "price_level"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        checkedAt = box.lString(.checkedAt)
        price = box.lDouble(.price)
        cheapestPrice = box.lDouble(.cheapestPrice)
        cheapestDepartureDate = box.lString(.cheapestDepartureDate)
        cheapestReturnDate = box.lString(.cheapestReturnDate)
        priceLevel = box.lString(.priceLevel)
    }
}

public struct FareWatch: Codable, Sendable, Hashable {
    public var id: Int
    public var planId: Int?
    public var originCode: String?
    public var destinationCode: String?
    public var originLabel: String?
    public var destinationLabel: String?
    public var departureDate: String?
    public var returnDate: String?
    public var numTravelers: Int?
    public var cabin: String?
    public var flexibleDays: Int?
    public var alertMode: String?
    public var targetPrice: Double?
    public var emailEnabled: Bool?
    public var status: String?
    public var baselinePrice: Double?
    public var lastPrice: Double?
    public var lowestPrice: Double?
    public var lowestPriceDate: String?
    public var lastNotifiedPrice: Double?
    public var lastNotifiedAt: String?
    public var googlePriceLevel: String?
    public var googleTypicalLow: Double?
    public var googleTypicalHigh: Double?
    public var checkCount: Int?
    public var failureCount: Int?
    public var problem: String?
    public var alreadyBelowTarget: Bool?
    public var alreadyLow: Bool?
    public var lastCheckedAt: String?
    public var nextCheckAt: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var history: [FareWatchHistoryPoint]?
    public var bookingUrl: String?
    public var alreadyWatching: Bool?
    /// Alerts 2.0: a quick-watch that has not had its first check yet (`lastPrice` is nil).
    public var pendingFirstCheck: Bool?
    public var checkStatus: String?
    public var notification: JSONValue?

    public init(
        id: Int,
        planId: Int? = nil,
        originCode: String? = nil,
        destinationCode: String? = nil,
        originLabel: String? = nil,
        destinationLabel: String? = nil,
        departureDate: String? = nil,
        returnDate: String? = nil,
        numTravelers: Int? = nil,
        cabin: String? = nil,
        flexibleDays: Int? = nil,
        alertMode: String? = nil,
        targetPrice: Double? = nil,
        emailEnabled: Bool? = nil,
        status: String? = nil,
        baselinePrice: Double? = nil,
        lastPrice: Double? = nil,
        lowestPrice: Double? = nil,
        lowestPriceDate: String? = nil,
        lastNotifiedPrice: Double? = nil,
        lastNotifiedAt: String? = nil,
        googlePriceLevel: String? = nil,
        googleTypicalLow: Double? = nil,
        googleTypicalHigh: Double? = nil,
        checkCount: Int? = nil,
        failureCount: Int? = nil,
        problem: String? = nil,
        alreadyBelowTarget: Bool? = nil,
        alreadyLow: Bool? = nil,
        lastCheckedAt: String? = nil,
        nextCheckAt: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        history: [FareWatchHistoryPoint]? = nil,
        bookingUrl: String? = nil,
        alreadyWatching: Bool? = nil,
        checkStatus: String? = nil,
        notification: JSONValue? = nil,
        pendingFirstCheck: Bool? = nil
    ) {
        self.id = id
        self.planId = planId
        self.originCode = originCode
        self.destinationCode = destinationCode
        self.originLabel = originLabel
        self.destinationLabel = destinationLabel
        self.departureDate = departureDate
        self.returnDate = returnDate
        self.numTravelers = numTravelers
        self.cabin = cabin
        self.flexibleDays = flexibleDays
        self.alertMode = alertMode
        self.targetPrice = targetPrice
        self.emailEnabled = emailEnabled
        self.status = status
        self.baselinePrice = baselinePrice
        self.lastPrice = lastPrice
        self.lowestPrice = lowestPrice
        self.lowestPriceDate = lowestPriceDate
        self.lastNotifiedPrice = lastNotifiedPrice
        self.lastNotifiedAt = lastNotifiedAt
        self.googlePriceLevel = googlePriceLevel
        self.googleTypicalLow = googleTypicalLow
        self.googleTypicalHigh = googleTypicalHigh
        self.checkCount = checkCount
        self.failureCount = failureCount
        self.problem = problem
        self.alreadyBelowTarget = alreadyBelowTarget
        self.alreadyLow = alreadyLow
        self.lastCheckedAt = lastCheckedAt
        self.nextCheckAt = nextCheckAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.history = history
        self.bookingUrl = bookingUrl
        self.alreadyWatching = alreadyWatching
        self.checkStatus = checkStatus
        self.notification = notification
        self.pendingFirstCheck = pendingFirstCheck
    }

    enum CodingKeys: String, CodingKey {
        case id
        case planId = "plan_id"
        case originCode = "origin_code"
        case destinationCode = "destination_code"
        case originLabel = "origin_label"
        case destinationLabel = "destination_label"
        case departureDate = "departure_date"
        case returnDate = "return_date"
        case numTravelers = "num_travelers"
        case cabin
        case flexibleDays = "flexible_days"
        case alertMode = "alert_mode"
        case targetPrice = "target_price"
        case emailEnabled = "email_enabled"
        case status
        case baselinePrice = "baseline_price"
        case lastPrice = "last_price"
        case lowestPrice = "lowest_price"
        case lowestPriceDate = "lowest_price_date"
        case lastNotifiedPrice = "last_notified_price"
        case lastNotifiedAt = "last_notified_at"
        case googlePriceLevel = "google_price_level"
        case googleTypicalLow = "google_typical_low"
        case googleTypicalHigh = "google_typical_high"
        case checkCount = "check_count"
        case failureCount = "failure_count"
        case problem
        case alreadyBelowTarget = "already_below_target"
        case alreadyLow = "already_low"
        case lastCheckedAt = "last_checked_at"
        case nextCheckAt = "next_check_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case history
        case bookingUrl = "booking_url"
        case alreadyWatching = "already_watching"
        case checkStatus = "check_status"
        case notification
        case pendingFirstCheck = "pending_first_check"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.reqInt(.id)
        planId = box.lInt(.planId)
        originCode = box.lString(.originCode)
        destinationCode = box.lString(.destinationCode)
        originLabel = box.lString(.originLabel)
        destinationLabel = box.lString(.destinationLabel)
        departureDate = box.lString(.departureDate)
        returnDate = box.lString(.returnDate)
        numTravelers = box.lInt(.numTravelers)
        cabin = box.lString(.cabin)
        flexibleDays = box.lInt(.flexibleDays)
        alertMode = box.lString(.alertMode)
        targetPrice = box.lDouble(.targetPrice)
        emailEnabled = box.lBool(.emailEnabled)
        status = box.lString(.status)
        baselinePrice = box.lDouble(.baselinePrice)
        lastPrice = box.lDouble(.lastPrice)
        lowestPrice = box.lDouble(.lowestPrice)
        lowestPriceDate = box.lString(.lowestPriceDate)
        lastNotifiedPrice = box.lDouble(.lastNotifiedPrice)
        lastNotifiedAt = box.lString(.lastNotifiedAt)
        googlePriceLevel = box.lString(.googlePriceLevel)
        googleTypicalLow = box.lDouble(.googleTypicalLow)
        googleTypicalHigh = box.lDouble(.googleTypicalHigh)
        checkCount = box.lInt(.checkCount)
        failureCount = box.lInt(.failureCount)
        problem = box.lString(.problem)
        alreadyBelowTarget = box.lBool(.alreadyBelowTarget)
        alreadyLow = box.lBool(.alreadyLow)
        lastCheckedAt = box.lString(.lastCheckedAt)
        nextCheckAt = box.lString(.nextCheckAt)
        createdAt = box.lString(.createdAt)
        updatedAt = box.lString(.updatedAt)
        history = box.lAny([FareWatchHistoryPoint].self, .history)
        bookingUrl = box.lString(.bookingUrl)
        alreadyWatching = box.lBool(.alreadyWatching)
        checkStatus = box.lString(.checkStatus)
        notification = box.lAny(JSONValue.self, .notification)
        pendingFirstCheck = box.lBool(.pendingFirstCheck)
    }
}

public struct NewFareWatch: Codable, Sendable, Hashable {
    public var planId: Int?
    public var origin: String?
    public var destination: String?
    public var destinations: [String]?
    public var departureDate: String?
    public var returnDate: String?
    public var numTravelers: Int?
    public var alertMode: String?
    public var targetPrice: Double?
    public var flexibleDays: Int?
    public var emailEnabled: Bool?

    public init(
        planId: Int? = nil,
        origin: String? = nil,
        destination: String? = nil,
        destinations: [String]? = nil,
        departureDate: String? = nil,
        returnDate: String? = nil,
        numTravelers: Int? = nil,
        alertMode: String? = nil,
        targetPrice: Double? = nil,
        flexibleDays: Int? = nil,
        emailEnabled: Bool? = nil
    ) {
        self.planId = planId
        self.origin = origin
        self.destination = destination
        self.destinations = destinations
        self.departureDate = departureDate
        self.returnDate = returnDate
        self.numTravelers = numTravelers
        self.alertMode = alertMode
        self.targetPrice = targetPrice
        self.flexibleDays = flexibleDays
        self.emailEnabled = emailEnabled
    }

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id"
        case origin
        case destination
        case destinations
        case departureDate = "departure_date"
        case returnDate = "return_date"
        case numTravelers = "num_travelers"
        case alertMode = "alert_mode"
        case targetPrice = "target_price"
        case flexibleDays = "flexible_days"
        case emailEnabled = "email_enabled"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        planId = box.lInt(.planId)
        origin = box.lString(.origin)
        destination = box.lString(.destination)
        destinations = box.lAny([String].self, .destinations)
        departureDate = box.lString(.departureDate)
        returnDate = box.lString(.returnDate)
        numTravelers = box.lInt(.numTravelers)
        alertMode = box.lString(.alertMode)
        targetPrice = box.lDouble(.targetPrice)
        flexibleDays = box.lInt(.flexibleDays)
        emailEnabled = box.lBool(.emailEnabled)
    }
}
