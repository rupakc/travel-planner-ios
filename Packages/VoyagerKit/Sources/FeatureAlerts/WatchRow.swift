import Foundation
import VoyagerModel

/// Parses the backend's ISO 8601 timestamps (`...Z`, with or without fractional seconds) and `yyyy-MM-dd` days.
enum AlertDates {
    static func timestamp(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // Naive timestamps (no zone) are UTC on this backend.
        let naive = ISO8601DateFormatter()
        naive.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        naive.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return naive.date(from: String(text.prefix(19)))
    }

    /// A `yyyy-MM-dd` day as noon UTC, so formatting in UTC never shifts the day.
    static func day(_ text: String?) -> Date? {
        guard let text, text.count >= 10 else { return nil }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

/// One watch (a fare watch or a price watch) in the list, reduced to what the card shows.
public struct WatchRow: Identifiable, Equatable, Sendable {
    public var kind: WatchKind
    public var watchID: Int
    public var title: String
    /// Backend-supplied subtitle for price watches; fares build theirs from `startDay`/`endDay`.
    public var subtitle: String?
    public var startDay: Date?
    public var endDay: Date?
    public var travellers: Int?
    public var currency: String
    public var status: String
    public var price: Double?
    public var baseline: Double?
    public var lowest: Double?
    public var checkedAt: Date?
    public var nextCheckAt: Date?
    public var alertMode: String
    public var target: Double?
    public var flexible: Bool
    public var emailEnabled: Bool
    public var isEstimate: Bool
    /// The frozen estimate a watch shows while it has no observed price (`last_observation.observed.estimate`).
    public var estimatePrice: Double?
    public var problem: String?
    public var link: URL?
    public var history: [Double]

    public var id: String { "\(kind.rawValue)-\(watchID)" }
    public var isPaused: Bool { status == "paused" }
    public var isPast: Bool { status == "expired" }
    public var isErrored: Bool { status == "error" }
    /// Active but not yet priced.
    public var isPending: Bool { price == nil && status == "active" }
    public var belowTarget: Bool { alertMode == "below_target" && target != nil }
    /// Fares can also watch the dates around the trip.
    public var supportsFlexible: Bool { kind == .flight }

    public init(
        kind: WatchKind, watchID: Int, title: String, subtitle: String? = nil, startDay: Date? = nil,
        endDay: Date? = nil, travellers: Int? = nil, currency: String = "USD", status: String = "active",
        price: Double? = nil, baseline: Double? = nil, lowest: Double? = nil, checkedAt: Date? = nil,
        nextCheckAt: Date? = nil, alertMode: String = "any_drop", target: Double? = nil, flexible: Bool = false,
        emailEnabled: Bool = false, isEstimate: Bool = false, estimatePrice: Double? = nil, problem: String? = nil, link: URL? = nil,
        history: [Double] = []
    ) {
        self.kind = kind
        self.watchID = watchID
        self.title = title
        self.subtitle = subtitle
        self.startDay = startDay
        self.endDay = endDay
        self.travellers = travellers
        self.currency = currency
        self.status = status
        self.price = price
        self.baseline = baseline
        self.lowest = lowest
        self.checkedAt = checkedAt
        self.nextCheckAt = nextCheckAt
        self.alertMode = alertMode
        self.target = target
        self.flexible = flexible
        self.emailEnabled = emailEnabled
        self.isEstimate = isEstimate
        self.estimatePrice = estimatePrice
        self.problem = problem
        self.link = link
        self.history = history
    }

    init(_ watch: FareWatch) {
        let origin = watch.originLabel ?? watch.originCode ?? ""
        let destination = watch.destinationLabel ?? watch.destinationCode ?? ""
        self.init(
            kind: .flight, watchID: watch.id, title: "\(origin) → \(destination)",
            startDay: AlertDates.day(watch.departureDate), endDay: AlertDates.day(watch.returnDate),
            travellers: watch.numTravelers, currency: "USD", status: watch.status ?? "active",
            price: watch.lastPrice, baseline: watch.baselinePrice, lowest: watch.lowestPrice,
            checkedAt: AlertDates.timestamp(watch.lastCheckedAt), nextCheckAt: AlertDates.timestamp(watch.nextCheckAt),
            alertMode: watch.alertMode ?? "any_drop", target: watch.targetPrice,
            flexible: (watch.flexibleDays ?? 0) > 0, emailEnabled: watch.emailEnabled ?? false,
            problem: watch.problem, link: watch.bookingUrl.flatMap(URL.init(string:)),
            history: (watch.history ?? []).compactMap(\.price))
    }

    init(_ watch: PriceWatch) {
        // The server freezes an estimate as status "unavailable" with `observed: {estimate: {price, source}, frozen: true}`
        // and no observed price; it never sends status "estimate".
        let observation = watch.lastObservation
        let estimate = observation?.observed?["estimate"]["price"].double
        let frozen = observation?.observed?["frozen"].bool == true
        let isEstimate = observation?.price == nil && watch.lastPrice == nil && (estimate != nil || frozen)
        self.init(
            kind: watch.kind ?? .hotel, watchID: watch.id, title: watch.title ?? "", subtitle: watch.subtitle,
            currency: watch.currency ?? "USD", status: watch.status ?? "active", price: watch.lastPrice,
            baseline: watch.baselinePrice, lowest: watch.lowestPrice,
            checkedAt: AlertDates.timestamp(watch.lastCheckedAt), nextCheckAt: AlertDates.timestamp(watch.nextCheckAt),
            alertMode: watch.alertMode ?? "any_drop", target: watch.targetPrice,
            emailEnabled: watch.emailEnabled ?? false,
            isEstimate: isEstimate, estimatePrice: isEstimate ? estimate : nil, problem: watch.problem,
            link: (watch.link ?? watch.lastObservation?.link).flatMap(URL.init(string:)),
            history: (watch.history ?? []).compactMap(\.price))
    }

    init(_ item: WatchItem) {
        switch item {
        case .fare(let watch): self.init(watch)
        case .price(let watch): self.init(watch)
        }
    }
}
