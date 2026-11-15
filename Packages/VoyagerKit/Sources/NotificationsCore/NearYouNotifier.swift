import Domain
import Foundation
import VoyagerModel

/// Where the person is, read once, in memory only (never written anywhere by this module).
public struct NearYouLocation: Sendable, Equatable {
    public var lat: Double
    public var lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

/// Whether a trip is under way. "Near you" runs only `onTheRoad`.
public enum NearYouPhase: Sendable, Equatable {
    case onTheRoad
    case other

    /// `onTheRoad` when today (in `calendar`) is between a saved plan's `departure_date` and `return_date`, both included.
    public static func of(plans: [PlanSummary], now: Date, calendar: Calendar = .current) -> NearYouPhase {
        let today = calendar.startOfDay(for: now)
        for plan in plans {
            guard let start = TripReminderScheduler.day(plan.searchData["departure_date"], calendar) else { continue }
            let end = TripReminderScheduler.day(plan.searchData["return_date"], calendar) ?? start
            if start <= today && today <= max(start, end) { return .onTheRoad }
        }
        return .other
    }
}

/// What the notifier needs to know about the person's choices.
public struct NearYouRules: Sendable {
    /// The Settings "Near me suggestions" switch of this device (off by default).
    public var deviceOptIn: Bool
    /// The notification settings (`categories.nearby`, quiet hours, daily cap); nil is an older server without them.
    public var settings: NotificationSettings?

    public init(deviceOptIn: Bool, settings: NotificationSettings? = nil) {
        self.deviceOptIn = deviceOptIn
        self.settings = settings
    }
}

public enum NearYouSkip: Sendable, Equatable {
    case notOnTrip, busy, rulesUnavailable, deviceOptOut, categoryOff, quietHours, gateDropped
    case notAuthorized, noLocation, throttled, requestFailed
}

public enum NearYouResult: Sendable, Equatable {
    case posted(personalized: Bool)
    case skipped(NearYouSkip)
}

/// "Near you" (R10): when the app becomes active during a trip, one local notification about something near the person.
///
/// Privacy: when-in-use location only (the caller reads it, and only after every cheap check passed); no background
/// location, no geofencing; the only network call is the existing non-grounded `POST /nearby` (v1, never
/// `sections: true`), whose coordinates go nowhere else, into no telemetry and no log. The answer is turned into text
/// and dropped; nothing location-like is stored (the per-cell throttle lives in memory, so a relaunch forgets it).
/// Rules: the device switch, the `nearby` category switch, quiet hours and the daily cap through `NotificationGate`
/// (a held notification is skipped, never queued: the place would be stale), at most one per ~500 m cell per 6 h.
public final class NearYouNotifier: @unchecked Sendable {
    public static let idPrefix = NearbyInvite.idPrefix
    public static let shownKeyPrefix = "voyager.nearyou.shown"
    /// A cell notifies at most this often.
    static let throttle: TimeInterval = 6 * 3600
    /// Cell size in metres.
    static let cellMetres = 500.0
    static let maxCells = 64

    private let nearby: any NearbyRepository
    private let center: any NotificationCenterClient
    private let defaults: UserDefaults
    private let loadRules: @Sendable () async -> NearYouRules?
    private let copy: NearYouTemplates.Copy
    private let lock = NSLock()
    private var visits: [String: Date] = [:]
    private var running = false

    public init(
        nearby: any NearbyRepository,
        center: any NotificationCenterClient = SystemNotificationCenter(),
        defaults: UserDefaults = .standard,
        copy: NearYouTemplates.Copy = .catalogue,
        rules: @escaping @Sendable () async -> NearYouRules?
    ) {
        self.nearby = nearby
        self.center = center
        self.defaults = defaults
        self.copy = copy
        self.loadRules = rules
    }

    /// Called when the scene becomes active. `location` is asked only after every check that needs no location passed.
    @discardableResult
    public func evaluate(
        location: @Sendable () async -> NearYouLocation?, phase: NearYouPhase, now: Date = Date()
    ) async -> NearYouResult {
        guard phase == .onTheRoad else { return .skipped(.notOnTrip) }
        guard begin() else { return .skipped(.busy) }
        defer { end() }
        guard let rules = await loadRules() else { return .skipped(.rulesUnavailable) }
        if let skip = check(rules, now: now) { return .skipped(skip) }
        guard await center.isAuthorized() else { return .skipped(.notAuthorized) }
        guard let here = await location() else { return .skipped(.noLocation) }
        let cell = Self.cell(here)
        guard !isThrottled(cell, now: now) else { return .skipped(.throttled) }
        guard let content = await fetchContent(here) else { return .skipped(.requestFailed) }
        let posted = await center.add(NearbyInvite.notification(id: "nearyou", title: content.title, body: content.body))
        guard posted else { return .skipped(.requestFailed) }
        markShown(cell, now: now, settings: rules.settings)
        return .posted(personalized: content.personalized)
    }

    /// One v1 `POST /nearby` (no `sections`, so no Google Maps grounding: its results may not be kept or scheduled),
    /// turned into text. Nil when the call fails (nothing is posted and the throttle is not used up).
    private func fetchContent(_ here: NearYouLocation) async -> NearYouTemplates.Content? {
        do {
            let response = try await nearby.nearby(NearbyRequest(lat: here.lat, lng: here.lng, limit: 1))
            return NearYouTemplates.content(for: response, copy: copy)
        } catch {
            return nil
        }
    }

    // MARK: Rules

    private func check(_ rules: NearYouRules, now: Date) -> NearYouSkip? {
        guard rules.deviceOptIn else { return .deviceOptOut }
        guard let settings = rules.settings else { return nil }
        guard settings.isEnabled(.nearby) else { return .categoryOff }
        let row = AppNotification(id: 0, kind: NotificationTemplateKey.nearbyArrival)
        switch NotificationGate.decide(
            row: row, settings: settings, now: now, deliveredToday: shownToday(now: now, settings: settings)) {
        case .deliverNow: return nil
        case .holdUntil: return .quietHours
        case .drop: return .gateDropped
        }
    }

    // MARK: State (no location is ever persisted)

    private func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if running { return false }
        running = true
        return true
    }

    private func end() {
        lock.lock()
        running = false
        lock.unlock()
    }

    private func isThrottled(_ cell: String, now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        visits = visits.filter { now.timeIntervalSince($0.value) < Self.throttle }
        guard let last = visits[cell] else { return false }
        return now.timeIntervalSince(last) < Self.throttle
    }

    private func markShown(_ cell: String, now: Date, settings: NotificationSettings?) {
        lock.lock()
        visits[cell] = now
        if visits.count > Self.maxCells, let oldest = visits.min(by: { $0.value < $1.value })?.key { visits[oldest] = nil }
        lock.unlock()
        let day = AlertPoller.dayKey(now, settings)
        var counts = defaults.dictionary(forKey: Self.shownKeyPrefix) as? [String: Int] ?? [:]
        counts = counts.filter { $0.key >= day }
        counts[day, default: 0] += 1
        defaults.set(counts, forKey: Self.shownKeyPrefix)
    }

    /// Near-you notifications this device showed today (a count, no place).
    private func shownToday(now: Date, settings: NotificationSettings?) -> Int {
        let counts = defaults.dictionary(forKey: Self.shownKeyPrefix) as? [String: Int]
        return counts?[AlertPoller.dayKey(now, settings)] ?? 0
    }

    /// A grid cell of about `cellMetres` as an in-memory key.
    static func cell(_ here: NearYouLocation) -> String {
        let latStep = cellMetres / 111_320
        let lngStep = latStep / max(cos(here.lat * .pi / 180), 0.01)
        return "\(Int((here.lat / latStep).rounded(.down))):\(Int((here.lng / lngStep).rounded(.down)))"
    }
}
