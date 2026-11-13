import Foundation
import L10n
import VoyagerEnv
import VoyagerModel

/// Local trip reminders: T-7 (visa, packing), T-1 (flight, weather), 08:00 on each trip day and the last day
/// (check-out). Identifier `trip-<planID>-<kind>`; at most `maxPending` are kept (iOS caps pending at 64).
public enum TripReminderScheduler {
    public static let maxPending = 60
    public static let idPrefix = "trip-"
    /// A trip longer than this gets day reminders for its first days only.
    static let maxTripDays = 30

    /// Copy for the reminders; the default reads the `mobile:reminders.*` catalogue in the app language.
    public struct Text: Sendable {
        public var t7Title: @Sendable (String) -> String
        public var t7Body: @Sendable () -> String
        public var t1Title: @Sendable (String) -> String
        public var t1Body: @Sendable () -> String
        public var dayTitle: @Sendable (Int, String) -> String
        public var dayBody: @Sendable () -> String
        public var lastDayTitle: @Sendable (String) -> String
        public var lastDayBody: @Sendable () -> String

        public static let catalogue = Text(
            t7Title: { L10n.text(K.mobile.reminders.t7Title, ["destination": $0]) },
            t7Body: { L10n.text(K.mobile.reminders.t7Body) },
            t1Title: { L10n.text(K.mobile.reminders.t1Title, ["destination": $0]) },
            t1Body: { L10n.text(K.mobile.reminders.t1Body) },
            dayTitle: { L10n.text(K.mobile.reminders.dayTitle, ["day": String($0), "destination": $1]) },
            dayBody: { L10n.text(K.mobile.reminders.dayBody) },
            lastDayTitle: { L10n.text(K.mobile.reminders.lastDayTitle, ["destination": $0]) },
            lastDayBody: { L10n.text(K.mobile.reminders.lastDayBody) }
        )
    }

    /// Fire times are device-local (the calendar's time zone): 08:00 means 08:00 wherever the phone is.
    /// Replaces every pending trip reminder with those for `plans`. Does nothing when notifications are not
    /// allowed (any trip reminders still pending are removed).
    public static func reschedule(
        plans: [PlanSummary],
        center: any NotificationCenterClient = SystemNotificationCenter(),
        now: Date = Date(),
        calendar: Calendar = .current,
        text: Text = .catalogue
    ) async {
        // One reschedule at a time: two overlapping runs would interleave their remove and add steps.
        await gate.run {
            await replace(plans: plans, center: center, now: now, calendar: calendar, text: text)
        }
    }

    private static let gate = Gate()

    private actor Gate {
        private var tail: Task<Void, Never>?
        func run(_ operation: @escaping @Sendable () async -> Void) async {
            let previous = tail
            let task = Task {
                await previous?.value
                await operation()
            }
            tail = task
            await task.value
        }
    }

    private static func replace(
        plans: [PlanSummary],
        center: any NotificationCenterClient,
        now: Date,
        calendar: Calendar,
        text: Text
    ) async {
        let stale = await center.pendingIdentifiers().filter { $0.hasPrefix(idPrefix) }
        if !stale.isEmpty { await center.removePending(identifiers: stale) }
        guard await center.isAuthorized() else { return }
        for item in reminders(for: plans, now: now, calendar: calendar, text: text) {
            await center.add(item)
        }
    }

    /// Reads the signed-in user's saved plans and reschedules from them (launch, foreground). Signed out: clears
    /// the trip reminders. Failures leave the pending reminders as they are.
    @MainActor
    public static func refresh(env: AppEnvironment, center: any NotificationCenterClient = SystemNotificationCenter()) async {
        guard env.auth.phase == .signedIn else {
            await purgeAccountNotifications(center: center)
            return
        }
        guard let plans = try? await env.repos.plans.list() else { return }
        await reschedule(plans: plans, center: center)
    }

    /// Removes the trip reminders and alert notifications (pending and delivered) of the previous account.
    public static func purgeAccountNotifications(center: any NotificationCenterClient = SystemNotificationCenter()) async {
        await center.purge(prefixes: [idPrefix, AlertPoller.idPrefix])
    }

    /// Sign-out or user switch: clears the old account's notifications, then loads the new user's trips.
    @MainActor
    public static func accountChanged(env: AppEnvironment, center: any NotificationCenterClient = SystemNotificationCenter()) async {
        await purgeAccountNotifications(center: center)
        await refresh(env: env, center: center)
    }

    /// The reminders to schedule, soonest first, future ones only, at most `maxPending`.
    public static func reminders(
        for plans: [PlanSummary],
        now: Date,
        calendar: Calendar = .current,
        text: Text = .catalogue
    ) -> [LocalNotification] {
        var timed: [(Date, LocalNotification)] = []
        for plan in plans {
            timed += reminders(for: plan, now: now, calendar: calendar, text: text)
        }
        timed.sort { $0.0 == $1.0 ? $0.1.id < $1.1.id : $0.0 < $1.0 }
        return timed.prefix(maxPending).map(\.1)
    }

    private static func reminders(
        for plan: PlanSummary,
        now: Date,
        calendar: Calendar,
        text: Text
    ) -> [(Date, LocalNotification)] {
        guard let start = day(plan.searchData["departure_date"], calendar) else { return [] }
        var end = day(plan.searchData["return_date"], calendar) ?? start
        if end < start { end = start }
        let destination = destinationName(plan)
        var out: [(Date, LocalNotification)] = []

        func add(_ kind: String, dayOffset: Int, from base: Date, hour: Int, title: String, body: String) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: base),
                let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date), fire > now
            else { return }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            out.append((fire, LocalNotification(
                id: "\(idPrefix)\(plan.id)-\(kind)", title: title, body: body, fireComponents: parts,
                userInfo: ["route": "trip", "plan_id": String(plan.id)]
            )))
        }

        add("t7", dayOffset: -7, from: start, hour: 9, title: text.t7Title(destination), body: text.t7Body())
        add("t1", dayOffset: -1, from: start, hour: 18, title: text.t1Title(destination), body: text.t1Body())
        let span = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        // Day reminders cover the first days (never the last); the last day always gets its own reminder.
        for index in 0..<min(max(span, 1), maxTripDays) {
            add("day\(index + 1)", dayOffset: index, from: start, hour: 8,
                title: text.dayTitle(index + 1, destination), body: text.dayBody())
        }
        // A one-day trip checks out the same day, later in the morning than its day reminder.
        add("last", dayOffset: span, from: start, hour: span == 0 ? 11 : 8,
            title: text.lastDayTitle(destination), body: text.lastDayBody())
        return out
    }

    private static func destinationName(_ plan: PlanSummary) -> String {
        let raw = plan.searchData["destination"].string ?? plan.name ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(80))
    }

    /// `yyyy-MM-dd` (a longer ISO string is cut to its date) at the start of that day, in `calendar`.
    static func day(_ value: JSONValue, _ calendar: Calendar) -> Date? {
        guard let raw = value.string else { return nil }
        let parts = raw.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let dayNumber = Int(parts[2]),
            (1...12).contains(month), (1...31).contains(dayNumber), (1970...2200).contains(year)
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: dayNumber))
    }
}
