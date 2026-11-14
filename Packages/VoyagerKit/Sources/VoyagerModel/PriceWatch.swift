import Foundation

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
    /// Alerts 2.0: a quick-watch that has not had its first check yet (`lastPrice` is nil).
    public var pendingFirstCheck: Bool?
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
        notification: JSONValue? = nil,
        pendingFirstCheck: Bool? = nil
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
        self.pendingFirstCheck = pendingFirstCheck
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
        case pendingFirstCheck = "pending_first_check"
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
        pendingFirstCheck = box.lBool(.pendingFirstCheck)
    }
}

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
