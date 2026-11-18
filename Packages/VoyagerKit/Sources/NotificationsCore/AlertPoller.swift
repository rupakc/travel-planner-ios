import Domain
import Foundation
import Networking
import VoyagerModel

/// What the poller needs to apply the delivery rules to a row (R9). `settings` nil is an older server without
/// categories: every row is shown as before. Without `notifications_v2` push the poller is the only way a row reaches
/// the phone; with server push live it is only a safety net (see `AlertPoller.safetyNetAge`).
public struct PollContext: Sendable {
    public var settings: NotificationSettings?
    public var prefs: AlertPrefs?
    public var showsGame: Bool
    public var serverPushLive: Bool
    /// The phone schedules the T-30, T-7, T-1 and morning reminders itself (`ReminderPolicy`), so the server's
    /// `trip_t30`/`trip_t7`/`trip_t1`/`trip_morning` rows are not shown again (M7: the local reminder is the one
    /// source while server push is not live; once it is live the server's push is, and these rows are a safety net).
    public var localTripReminders: Bool

    public init(
        settings: NotificationSettings? = nil, prefs: AlertPrefs? = nil, showsGame: Bool = false, serverPushLive: Bool = false,
        localTripReminders: Bool = false
    ) {
        self.localTripReminders = localTripReminders
        self.settings = settings
        self.prefs = prefs
        self.showsGame = showsGame
        self.serverPushLive = serverPushLive
    }
}

/// Turns unread server notifications into local ones, once per id, through `NotificationGate` (category switch,
/// `instant = targets_only`, quiet hours, daily caps): a row the gate holds is scheduled for the window's end, a row it
/// drops is marked seen without a banner (the inbox still has it). Seen ids live in `UserDefaults` (at most 200); a push
/// the phone already received is recorded there too (`recordPush`), so a push and a poll never show the same row twice.
/// A 404 from the endpoint (an older backend) disables polling for the launch.
public final class AlertPoller: @unchecked Sendable {
    public static let seenKeyPrefix = "voyager.alertpoll.seen"
    public static let idPrefix = "alert-"
    public static let maxSeen = 200
    /// More than this many new rows at once (a first poll) show only the newest ones.
    static let maxPerPoll = 5
    /// With server push live a row younger than this is left for the push; older and never delivered is shown here.
    static let safetyNetAge: TimeInterval = 3600
    public static let shownKeyPrefix = "voyager.alertpoll.shown"

    private let repo: any NotificationsRepository
    private let center: any NotificationCenterClient
    private let defaults: UserDefaults
    private let context: @Sendable () async -> PollContext?
    private let now: @Sendable () -> Date
    /// The signed-in user (seen ids are kept per user, so a switch starts with a first poll).
    public let userID: String
    private let lock = NSLock()
    private var disabled = false

    public init(
        repo: any NotificationsRepository,
        userID: String,
        center: any NotificationCenterClient = SystemNotificationCenter(),
        defaults: UserDefaults = .standard,
        context: @escaping @Sendable () async -> PollContext? = { PollContext() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.now = now
        self.userID = userID
        self.repo = repo
        self.center = center
        self.defaults = defaults
    }

    public var seenKey: String { Self.seenKeyPrefix + "." + userID.lowercased() }
    private var shownKey: String { Self.shownKeyPrefix + "." + userID.lowercased() }

    /// A server push for row `id` reached this phone: the poller must not show the same row again.
    public static func recordPush(id: Int, userID: String, defaults: UserDefaults = .standard) {
        let key = seenKeyPrefix + "." + userID.lowercased()
        var seen = defaults.array(forKey: key)?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
        guard !seen.contains(id) else { return }
        seen.append(id)
        defaults.set(Array(seen.suffix(maxSeen)), forKey: key)
    }

    public var isDisabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return disabled
    }

    private func disable() {
        lock.lock()
        disabled = true
        lock.unlock()
    }

    /// Never throws. Returns how many local notifications were posted (or scheduled, for a held row).
    @discardableResult
    public func poll() async -> Int {
        guard !isDisabled, await center.isAuthorized(), let page = await fetchPage() else { return 0 }
        var seen = defaults.array(forKey: seenKey)?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
        let known = Set(seen)
        // Newest first: when more than `maxPerPoll` are new, the newest ones are shown.
        let fresh = page.items.filter { !known.contains($0.id) }.sorted { $0.id > $1.id }
        // Rules unreadable (settings failed to load): try again at the next poll rather than break a rule.
        guard !fresh.isEmpty, let rules = await context() else { return 0 }
        let outcome = await deliver(fresh, rules)
        seen.append(contentsOf: outcome.done.sorted())
        defaults.set(Array(seen.suffix(Self.maxSeen)), forKey: seenKey)
        return outcome.posted
    }

    private func fetchPage() async -> NotificationsPage? {
        do {
            return try await repo.page(unreadOnly: true, limit: 50, offset: 0)
        } catch let error as APIError {
            if case .notFound = error { disable() }
            return nil
        } catch {
            return nil
        }
    }

    private struct Outcome {
        var posted = 0
        /// Ids not worth showing again: posted, held, dropped by a rule, or too old.
        var done: [Int] = []
    }

    /// What happens to one row.
    private enum Verdict { case leave, done, show(DateComponents?) }

    private func deliver(_ fresh: [AppNotification], _ rules: PollContext) async -> Outcome {
        var delivered = Set<Int>()
        if rules.serverPushLive { delivered = await center.deliveredPushIDs() }
        let current = now()
        var shown = loadShown(today: Self.dayKey(current, rules.settings))
        var outcome = Outcome()
        var attempts = 0
        for item in fresh {
            switch verdict(item, rules, delivered: delivered, now: current, shown: shown, attempts: attempts) {
            case .leave:
                continue
            case .done:
                outcome.done.append(item.id)
            case .show(let fire):
                attempts += 1  // a failed add still used up one of the poll's slots
                let title = Self.clean(item.title) ?? Self.clean(item.body) ?? ""
                let body = Self.clean(item.title) == nil ? "" : (Self.clean(item.body) ?? "")
                // A failed add stays unseen, so the next poll tries again.
                guard await center.add(LocalNotification(
                    id: Self.idPrefix + String(item.id), title: title, body: body, fireComponents: fire,
                    userInfo: Self.userInfo(item))) else { continue }
                outcome.posted += 1
                outcome.done.append(item.id)
                let day = Self.dayKey(fire.flatMap { Calendar.current.date(from: $0) } ?? current, rules.settings)
                shown[day, default: [:]][Self.bucket(item), default: 0] += 1
            }
        }
        saveShown(shown, today: Self.dayKey(current, rules.settings))
        return outcome
    }

    private func verdict(
        _ item: AppNotification, _ rules: PollContext, delivered: Set<Int>, now: Date, shown: [String: [String: Int]],
        attempts: Int
    ) -> Verdict {
        if delivered.contains(item.id) { return .done }  // the push already showed it
        if rules.localTripReminders, Self.isLocallyRemindedTripKind(item.kind) { return .done }  // the local reminder is the one
        if rules.serverPushLive, Self.isYoung(item, now: now) { return .leave }  // the push may still arrive
        guard attempts < Self.maxPerPoll, (Self.clean(item.title) ?? Self.clean(item.body)) != nil else { return .done }
        guard let settings = rules.settings else { return .show(nil) }
        let day = Self.dayKey(now, settings)
        let decision = NotificationGate.decide(
            row: item, settings: settings, prefs: rules.prefs, now: now, showsGame: rules.showsGame,
            deliveredToday: shown[day]?[Self.bucket(item)] ?? 0)
        switch decision {
        case .drop: return .done
        case .deliverNow: return .show(nil)
        case .holdUntil(let due):
            return .show(Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due))
        }
    }

    private func loadShown(today: String) -> [String: [String: Int]] {
        guard let stored = defaults.dictionary(forKey: shownKey) as? [String: [String: Int]] else { return [:] }
        return stored.filter { $0.key >= today }
    }

    private func saveShown(_ shown: [String: [String: Int]], today: String) {
        defaults.set(shown.filter { $0.key >= today }, forKey: shownKey)
    }

    /// The cap bucket: the watch kind for price rows (per-kind caps), `other` for everything under `daily_cap`.
    static func bucket(_ item: AppNotification) -> String {
        NotificationCategory.of(kind: item.kind) == .priceDrops
            ? (NotificationGate.watchKind(of: item)?.rawValue ?? "other") : "other"
    }

    /// The local day (`yyyy-MM-dd`) in the account time zone, else the phone's.
    static func dayKey(_ date: Date, _ settings: NotificationSettings?) -> String {
        var calendar = Calendar(identifier: .gregorian)
        if let name = settings?.timezone, let zone = TimeZone(identifier: name) { calendar.timeZone = zone }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func isYoung(_ item: AppNotification, now: Date) -> Bool {
        guard let raw = item.createdAt else { return false }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let created = fractional.date(from: raw) ?? plain.date(from: raw) else { return false }
        return now.timeIntervalSince(created) < safetyNetAge
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }

    /// The trip-phase kinds the phone also schedules locally (`TripReminderScheduler`: T-30, T-7, T-1, day reminders).
    static func isLocallyRemindedTripKind(_ kind: String?) -> Bool {
        switch kind {
        case "trip_t30", "trip_t7", "trip_t1", "trip_morning": true
        default: false
        }
    }

    /// The tap payload. A price row (or a row without a known kind) is `route: alerts` plus the watch the row is about
    /// when the server named one. Any other known kind (trip, weather, social, quiz) leaves `route` unset and carries
    /// `kind`, `plan_id`, `link` and `notification_id`, so a tap routes like a server push (`NotificationTarget`) and
    /// `notif_open` reports the kind's own category.
    static func userInfo(_ item: AppNotification) -> [String: String] {
        if let kind = item.kind, let category = NotificationCategory.of(kind: kind), category != .priceDrops {
            var info = ["kind": kind, "notification_id": String(item.id)]
            let link = item.data["link"].string.flatMap { $0.isEmpty ? nil : String($0.prefix(256)) }
            if let link { info["link"] = link }
            if let plan = planID(item, link: link) { info["plan_id"] = String(plan) }
            return info
        }
        var info = ["route": "alerts"]
        if let kind = item.data["kind"].string, WatchKind(rawValue: kind) != nil { info["kind"] = kind }
        if let value = item.data["watch_id"].double, value.isFinite, value >= 1, value <= 1e9 {
            info["watch_id"] = String(Int(value.rounded()))
        }
        return info
    }

    /// `data.plan_id`, else the id in a `/trips/<id>...` link.
    private static func planID(_ item: AppNotification, link: String?) -> Int? {
        if let value = item.data["plan_id"].double, value.isFinite, value >= 1, value <= 1e9 { return Int(value.rounded()) }
        guard let link, link.hasPrefix("/trips/") else { return nil }
        let id = link.dropFirst("/trips/".count).prefix { $0.isNumber }
        guard let number = Int(id), number > 0, number <= 1_000_000_000 else { return nil }
        return number
    }
}
