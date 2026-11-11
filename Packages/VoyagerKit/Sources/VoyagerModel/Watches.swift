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

/// A fare watch (`/api/fare-watches`). Prices are totals for the trip's travellers, in USD.
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
        notification: JSONValue? = nil
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
    }
}

public struct PriceObservation: Codable, Sendable, Hashable {
    public var price: Double?
    public var unitPrice: Double?
    public var status: String?
    public var source: String?
    public var link: String?
    public var breakdown: JSONValue?
    public var observed: JSONValue?
    public var observedAt: String?

    public init(
        price: Double? = nil,
        unitPrice: Double? = nil,
        status: String? = nil,
        source: String? = nil,
        link: String? = nil,
        breakdown: JSONValue? = nil,
        observed: JSONValue? = nil,
        observedAt: String? = nil
    ) {
        self.price = price
        self.unitPrice = unitPrice
        self.status = status
        self.source = source
        self.link = link
        self.breakdown = breakdown
        self.observed = observed
        self.observedAt = observedAt
    }

    enum CodingKeys: String, CodingKey {
        case price
        case unitPrice = "unit_price"
        case status
        case source
        case link
        case breakdown
        case observed
        case observedAt = "observed_at"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        price = box.lDouble(.price)
        unitPrice = box.lDouble(.unitPrice)
        status = box.lString(.status)
        source = box.lString(.source)
        link = box.lString(.link)
        breakdown = box.lAny(JSONValue.self, .breakdown)
        observed = box.lAny(JSONValue.self, .observed)
        observedAt = box.lString(.observedAt)
    }
}

public struct PriceWatchHistoryPoint: Codable, Sendable, Hashable {
    public var checkedAt: String?
    public var price: Double?
    public var breakdown: JSONValue?
    public var observed: JSONValue?

    public init(
        checkedAt: String? = nil,
        price: Double? = nil,
        breakdown: JSONValue? = nil,
        observed: JSONValue? = nil
    ) {
        self.checkedAt = checkedAt
        self.price = price
        self.breakdown = breakdown
        self.observed = observed
    }

    enum CodingKeys: String, CodingKey {
        case checkedAt = "checked_at"
        case price
        case breakdown
        case observed
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        checkedAt = box.lString(.checkedAt)
        price = box.lDouble(.price)
        breakdown = box.lAny(JSONValue.self, .breakdown)
        observed = box.lAny(JSONValue.self, .observed)
    }
}

/// A hotel, activity or trip price watch (`/api/price-watches`). Prices are totals in `currency`.
public struct PriceWatch: Codable, Sendable, Hashable {
    public var id: Int
    public var kind: WatchKind?
    public var planId: Int?
    public var title: String?
    public var subtitle: String?
    public var subject: JSONValue?
    public var currency: String?
    public var alertMode: String?
    public var targetPrice: Double?
    public var emailEnabled: Bool?
    public var status: String?
    public var baselinePrice: Double?
    public var lastPrice: Double?
    public var lowestPrice: Double?
    public var lastNotifiedPrice: Double?
    public var lastNotifiedAt: String?
    public var ownPeakPrice: Double?
    public var lastObservation: PriceObservation?
    public var link: String?
    public var expiresOn: String?
    public var checkCount: Int?
    public var failureCount: Int?
    public var unavailableCount: Int?
    public var problem: String?
    public var alreadyBelowTarget: Bool?
    public var lastCheckedAt: String?
    public var nextCheckAt: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var history: [PriceWatchHistoryPoint]?
    public var alreadyWatching: Bool?
    public var checkStatus: String?
    public var notification: JSONValue?

    public init(
        id: Int,
        kind: WatchKind? = nil,
        planId: Int? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        subject: JSONValue? = nil,
        currency: String? = nil,
        alertMode: String? = nil,
        targetPrice: Double? = nil,
        emailEnabled: Bool? = nil,
        status: String? = nil,
        baselinePrice: Double? = nil,
        lastPrice: Double? = nil,
        lowestPrice: Double? = nil,
        lastNotifiedPrice: Double? = nil,
        lastNotifiedAt: String? = nil,
        ownPeakPrice: Double? = nil,
        lastObservation: PriceObservation? = nil,
        link: String? = nil,
        expiresOn: String? = nil,
        checkCount: Int? = nil,
        failureCount: Int? = nil,
        unavailableCount: Int? = nil,
        problem: String? = nil,
        alreadyBelowTarget: Bool? = nil,
        lastCheckedAt: String? = nil,
        nextCheckAt: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        history: [PriceWatchHistoryPoint]? = nil,
        alreadyWatching: Bool? = nil,
        checkStatus: String? = nil,
        notification: JSONValue? = nil
    ) {
        self.id = id
        self.kind = kind
        self.planId = planId
        self.title = title
        self.subtitle = subtitle
        self.subject = subject
        self.currency = currency
        self.alertMode = alertMode
        self.targetPrice = targetPrice
        self.emailEnabled = emailEnabled
        self.status = status
        self.baselinePrice = baselinePrice
        self.lastPrice = lastPrice
        self.lowestPrice = lowestPrice
        self.lastNotifiedPrice = lastNotifiedPrice
        self.lastNotifiedAt = lastNotifiedAt
        self.ownPeakPrice = ownPeakPrice
        self.lastObservation = lastObservation
        self.link = link
        self.expiresOn = expiresOn
        self.checkCount = checkCount
        self.failureCount = failureCount
        self.unavailableCount = unavailableCount
        self.problem = problem
        self.alreadyBelowTarget = alreadyBelowTarget
        self.lastCheckedAt = lastCheckedAt
        self.nextCheckAt = nextCheckAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.history = history
        self.alreadyWatching = alreadyWatching
        self.checkStatus = checkStatus
        self.notification = notification
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case planId = "plan_id"
        case title
        case subtitle
        case subject
        case currency
        case alertMode = "alert_mode"
        case targetPrice = "target_price"
        case emailEnabled = "email_enabled"
        case status
        case baselinePrice = "baseline_price"
        case lastPrice = "last_price"
        case lowestPrice = "lowest_price"
        case lastNotifiedPrice = "last_notified_price"
        case lastNotifiedAt = "last_notified_at"
        case ownPeakPrice = "own_peak_price"
        case lastObservation = "last_observation"
        case link
        case expiresOn = "expires_on"
        case checkCount = "check_count"
        case failureCount = "failure_count"
        case unavailableCount = "unavailable_count"
        case problem
        case alreadyBelowTarget = "already_below_target"
        case lastCheckedAt = "last_checked_at"
        case nextCheckAt = "next_check_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case history
        case alreadyWatching = "already_watching"
        case checkStatus = "check_status"
        case notification
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.reqInt(.id)
        kind = box.lAny(WatchKind.self, .kind)
        planId = box.lInt(.planId)
        title = box.lString(.title)
        subtitle = box.lString(.subtitle)
        subject = box.lAny(JSONValue.self, .subject)
        currency = box.lString(.currency)
        alertMode = box.lString(.alertMode)
        targetPrice = box.lDouble(.targetPrice)
        emailEnabled = box.lBool(.emailEnabled)
        status = box.lString(.status)
        baselinePrice = box.lDouble(.baselinePrice)
        lastPrice = box.lDouble(.lastPrice)
        lowestPrice = box.lDouble(.lowestPrice)
        lastNotifiedPrice = box.lDouble(.lastNotifiedPrice)
        lastNotifiedAt = box.lString(.lastNotifiedAt)
        ownPeakPrice = box.lDouble(.ownPeakPrice)
        lastObservation = box.lAny(PriceObservation.self, .lastObservation)
        link = box.lString(.link)
        expiresOn = box.lString(.expiresOn)
        checkCount = box.lInt(.checkCount)
        failureCount = box.lInt(.failureCount)
        unavailableCount = box.lInt(.unavailableCount)
        problem = box.lString(.problem)
        alreadyBelowTarget = box.lBool(.alreadyBelowTarget)
        lastCheckedAt = box.lString(.lastCheckedAt)
        nextCheckAt = box.lString(.nextCheckAt)
        createdAt = box.lString(.createdAt)
        updatedAt = box.lString(.updatedAt)
        history = box.lAny([PriceWatchHistoryPoint].self, .history)
        alreadyWatching = box.lBool(.alreadyWatching)
        checkStatus = box.lString(.checkStatus)
        notification = box.lAny(JSONValue.self, .notification)
    }
}

/// `PATCH` body for either watch kind (`flexibleDays` is for fare watches only).
public struct WatchPatch: Codable, Sendable, Hashable {
    public var status: String?
    public var alertMode: String?
    public var targetPrice: Double?
    public var flexibleDays: Int?
    public var emailEnabled: Bool?

    public init(
        status: String? = nil,
        alertMode: String? = nil,
        targetPrice: Double? = nil,
        flexibleDays: Int? = nil,
        emailEnabled: Bool? = nil
    ) {
        self.status = status
        self.alertMode = alertMode
        self.targetPrice = targetPrice
        self.flexibleDays = flexibleDays
        self.emailEnabled = emailEnabled
    }

    enum CodingKeys: String, CodingKey {
        case status
        case alertMode = "alert_mode"
        case targetPrice = "target_price"
        case flexibleDays = "flexible_days"
        case emailEnabled = "email_enabled"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        status = box.lString(.status)
        alertMode = box.lString(.alertMode)
        targetPrice = box.lDouble(.targetPrice)
        flexibleDays = box.lInt(.flexibleDays)
        emailEnabled = box.lBool(.emailEnabled)
    }
}

/// `POST /api/fare-watches` body: a trip, or `planId`.
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

/// Which watch family an item belongs to. `flight` is a fare watch; the rest are price watches.
public enum WatchKind: String, Codable, Sendable, Hashable, CaseIterable {
    case flight, hotel, activity, trip
}

/// Either kind of watch, as answered by patch and check calls.
public enum WatchItem: Sendable, Hashable {
    case fare(FareWatch)
    case price(PriceWatch)
}

/// The item or search data to watch (SectionsUI builds it; `WatchCreateCoordinator` sends it).
public enum WatchRequest: Sendable, Hashable {
    case fare(JSONValue)
    case hotel(JSONValue)
    case activity(JSONValue)
    case trip(JSONValue)

    public var kind: WatchKind {
        switch self {
        case .fare: .flight
        case .hotel: .hotel
        case .activity: .activity
        case .trip: .trip
        }
    }

    public var spec: JSONValue {
        switch self {
        case .fare(let value), .hotel(let value), .activity(let value), .trip(let value): value
        }
    }
}

private struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// `POST /api/price-watches` body: `{"kind": "hotel", "hotel": <spec>, plan_id, alert_mode, ...}`.
/// The spec rides under the kind's own key.
public struct NewPriceWatch: Codable, Sendable, Hashable {
    public var kind: WatchKind
    public var spec: JSONValue
    public var planId: Int?
    public var alertMode: String?
    public var targetPrice: Double?
    public var targetCurrency: String?
    public var emailEnabled: Bool?

    public init(
        kind: WatchKind, spec: JSONValue, planId: Int? = nil, alertMode: String? = nil,
        targetPrice: Double? = nil, targetCurrency: String? = nil, emailEnabled: Bool? = nil
    ) {
        self.kind = kind
        self.spec = spec
        self.planId = planId
        self.alertMode = alertMode
        self.targetPrice = targetPrice
        self.targetCurrency = targetCurrency
        self.emailEnabled = emailEnabled
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: DynamicKey.self)
        let kind = try box.decode(WatchKind.self, forKey: DynamicKey("kind"))
        self.kind = kind
        spec = (try? box.decodeIfPresent(JSONValue.self, forKey: DynamicKey(kind.rawValue))) ?? .null
        planId = try? box.decodeIfPresent(Int.self, forKey: DynamicKey("plan_id"))
        alertMode = try? box.decodeIfPresent(String.self, forKey: DynamicKey("alert_mode"))
        targetPrice = try? box.decodeIfPresent(Double.self, forKey: DynamicKey("target_price"))
        targetCurrency = try? box.decodeIfPresent(String.self, forKey: DynamicKey("target_currency"))
        emailEnabled = try? box.decodeIfPresent(Bool.self, forKey: DynamicKey("email_enabled"))
    }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: DynamicKey.self)
        try box.encode(kind, forKey: DynamicKey("kind"))
        try box.encode(spec, forKey: DynamicKey(kind.rawValue))
        try box.encodeIfPresent(planId, forKey: DynamicKey("plan_id"))
        try box.encodeIfPresent(alertMode, forKey: DynamicKey("alert_mode"))
        try box.encodeIfPresent(targetPrice, forKey: DynamicKey("target_price"))
        try box.encodeIfPresent(targetCurrency, forKey: DynamicKey("target_currency"))
        try box.encodeIfPresent(emailEnabled, forKey: DynamicKey("email_enabled"))
    }
}

/// `POST /api/fare-watches/match` and `/api/price-watches/match` body. A flight match sends the
/// trip fields at the top level (like creating a fare watch); the other kinds send
/// `{"kind", "<kind>": spec, "plan_id"}`.
public struct WatchMatchQuery: Codable, Sendable, Hashable {
    public var kind: WatchKind
    public var spec: JSONValue
    public var planId: Int?

    public init(kind: WatchKind, spec: JSONValue, planId: Int? = nil) {
        self.kind = kind
        self.spec = spec
        self.planId = planId
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: DynamicKey.self)
        if let kind = try? box.decodeIfPresent(WatchKind.self, forKey: DynamicKey("kind")) {
            self.kind = kind
            spec = (try? box.decodeIfPresent(JSONValue.self, forKey: DynamicKey(kind.rawValue))) ?? .null
        } else {
            kind = .flight
            var fields: [String: JSONValue] = [:]
            for key in box.allKeys where key.stringValue != "plan_id" {
                fields[key.stringValue] = (try? box.decode(JSONValue.self, forKey: key)) ?? .null
            }
            spec = .object(fields)
        }
        planId = try? box.decodeIfPresent(Int.self, forKey: DynamicKey("plan_id"))
    }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: DynamicKey.self)
        if kind == .flight {
            if case .object(let fields) = spec {
                for key in fields.keys.sorted() { try box.encode(fields[key] ?? .null, forKey: DynamicKey(key)) }
            }
        } else {
            try box.encode(kind, forKey: DynamicKey("kind"))
            try box.encode(spec, forKey: DynamicKey(kind.rawValue))
        }
        try box.encodeIfPresent(planId, forKey: DynamicKey("plan_id"))
    }
}
