import Foundation
import Networking
import os
import Testing
import VoyagerModel

@testable import NotificationsCore

final class FakeCenter: NotificationCenterClient, Sendable {
    private struct State { var pending: [String: LocalNotification] = [:]; var requests = 0; var granted = true }
    private let state = OSAllocatedUnfairLock(initialState: State())
    init(granted: Bool = true) { state.withLock { $0.granted = granted } }

    var added: [LocalNotification] { state.withLock { Array($0.pending.values) } }
    var requests: Int { state.withLock { $0.requests } }
    func requestAuthorization() async -> Bool { state.withLock { $0.requests += 1; return $0.granted } }
    func isAuthorized() async -> Bool { state.withLock { $0.granted } }
    func add(_ notification: LocalNotification) async { state.withLock { $0.pending[notification.id] = notification } }
    func pendingIdentifiers() async -> [String] { state.withLock { Array($0.pending.keys) } }
    func removePending(identifiers: [String]) async {
        state.withLock { for id in identifiers { $0.pending[id] = nil } }
    }
}

final class FakeNotifications: NotificationsRepository, Sendable {
    private struct State { var items: [AppNotification] = []; var error: APIError?; var calls = 0 }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var items: [AppNotification] {
        get { state.withLock { $0.items } }
        set { state.withLock { $0.items = newValue } }
    }
    var error: APIError? {
        get { state.withLock { $0.error } }
        set { state.withLock { $0.error = newValue } }
    }
    var calls: Int { state.withLock { $0.calls } }

    func page(unreadOnly: Bool, limit: Int, offset: Int) async throws -> NotificationsPage {
        let (rows, failure) = state.withLock { s -> ([AppNotification], APIError?) in
            s.calls += 1
            return (s.items, s.error)
        }
        if let failure { throw failure }
        return NotificationsPage(items: rows, total: rows.count, unread: rows.count)
    }
    func unreadCount() async throws -> Int { items.count }
    func markRead(ids: [Int]?, all: Bool) async throws -> Int { 0 }
}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ iso: String) -> Date {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
}

private func plan(_ id: Int, from: String?, to: String?) -> PlanSummary {
    var data: [String: JSONValue] = ["destination": "Tokyo"]
    if let from { data["departure_date"] = .string(from) }
    if let to { data["return_date"] = .string(to) }
    return PlanSummary(id: id, name: "x", searchData: .object(data))
}

private let text = TripReminderScheduler.Text(
    t7Title: { "t7 \($0)" }, t7Body: { "b7" }, t1Title: { "t1 \($0)" }, t1Body: { "b1" },
    dayTitle: { "d\($0) \($1)" }, dayBody: { "bd" }, lastDayTitle: { "last \($0)" }, lastDayBody: { "bl" }
)

@Suite struct TripReminderTests {
    @Test func remindersForFutureTripOnly() async {
        let now = date("2027-03-01")
        let center = FakeCenter()
        let plans = [plan(1, from: "2027-03-20", to: "2027-03-23"), plan(2, from: "2026-01-01", to: "2026-01-05"),
                     plan(3, from: nil, to: nil), plan(4, from: "garbage", to: "2027-13-99")]
        await TripReminderScheduler.reschedule(plans: plans, center: center, now: now, calendar: utc, text: text)
        let ids = Set(center.added.map(\.id))
        #expect(ids == ["trip-1-t7", "trip-1-t1", "trip-1-day1", "trip-1-day2", "trip-1-day3", "trip-1-last"])
        let last = center.added.first { $0.id == "trip-1-last" }
        #expect(last?.fireComponents?.day == 23 && last?.fireComponents?.hour == 8)
        #expect(last?.title == "last Tokyo")
    }

    @Test func pastT7IsSkippedButLaterOnesKept() {
        let items = TripReminderScheduler.reminders(
            for: [plan(1, from: "2027-03-05", to: nil)], now: date("2027-03-01"), calendar: utc, text: text)
        #expect(items.map(\.id) == ["trip-1-t1", "trip-1-day1"])
    }

    @Test func capAt60() async {
        let plans = (1...10).map { plan($0, from: "2027-06-\(String(format: "%02d", $0 + 10))", to: "2027-07-10") }
        let center = FakeCenter()
        await TripReminderScheduler.reschedule(plans: plans, center: center, now: date("2027-01-01"), calendar: utc, text: text)
        #expect(center.added.count == 60)
        // Soonest first: the plan departing first keeps its T-7.
        #expect(center.added.contains { $0.id == "trip-1-t7" })
    }

    @Test func rescheduleReplacesTripRemindersOnly() async {
        let center = FakeCenter()
        await center.add(LocalNotification(id: "trip-9-t7", title: "old", body: ""))
        await center.add(LocalNotification(id: "alert-5", title: "keep", body: ""))
        await TripReminderScheduler.reschedule(plans: [], center: center, now: Date(), calendar: utc, text: text)
        #expect(Set(center.added.map(\.id)) == ["alert-5"])
    }

    @Test func notAuthorizedSchedulesNothing() async {
        let center = FakeCenter(granted: false)
        await TripReminderScheduler.reschedule(
            plans: [plan(1, from: "2027-03-20", to: nil)], center: center, now: date("2027-03-01"), calendar: utc, text: text)
        #expect(center.added.isEmpty)
    }
}

@Suite struct AlertPollerTests {
    private func defaults() -> UserDefaults {
        let name = "alertpoller-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    @Test func pollerDedupesSeenIDs() async {
        let repo = FakeNotifications()
        repo.items = [AppNotification(id: 1, title: "Drop", body: "NYC-TYO"), AppNotification(id: 2, title: "Drop 2")]
        let center = FakeCenter()
        let poller = AlertPoller(repo: repo, center: center, defaults: defaults())
        #expect(await poller.poll() == 2)
        #expect(await poller.poll() == 0)
        repo.items.append(AppNotification(id: 3, title: "New"))
        #expect(await poller.poll() == 1)
        #expect(Set(center.added.map(\.id)) == ["alert-1", "alert-2", "alert-3"])
    }

    @Test func seenIDsAreCappedAt200() async {
        let repo = FakeNotifications()
        repo.items = (1...300).map { AppNotification(id: $0, title: "t") }
        let store = defaults()
        let poller = AlertPoller(repo: repo, center: FakeCenter(), defaults: store)
        await poller.poll()
        #expect((store.array(forKey: AlertPoller.seenKey) ?? []).count == AlertPoller.maxSeen)
    }

    @Test func poller404Stops() async {
        let repo = FakeNotifications()
        repo.error = .notFound(nil)
        let poller = AlertPoller(repo: repo, center: FakeCenter(), defaults: defaults())
        #expect(await poller.poll() == 0)
        #expect(poller.isDisabled)
        _ = await poller.poll()
        #expect(repo.calls == 1)
    }

    @Test func otherErrorsDoNotDisable() async {
        let repo = FakeNotifications()
        repo.error = .network
        let poller = AlertPoller(repo: repo, center: FakeCenter(), defaults: defaults())
        _ = await poller.poll()
        #expect(!poller.isDisabled)
    }

    @Test func noPermissionMeansNoRequest() async {
        let repo = FakeNotifications()
        let poller = AlertPoller(repo: repo, center: FakeCenter(granted: false), defaults: defaults())
        _ = await poller.poll()
        #expect(repo.calls == 0)
    }

    @Test func looseWatchIDNeverTraps() {
        let item = AppNotification(id: 1, data: ["watch_id": 1e30, "kind": "flight"])
        #expect(AlertPoller.userInfo(item) == ["route": "alerts", "kind": "flight"])
    }
}

@Suite struct RoutingTests {
    @Test func tapRoutesToAlerts() {
        let item = AppNotification(id: 1, data: ["watch_id": 7, "kind": "hotel"])
        #expect(NotificationRouting.route(AlertPoller.userInfo(item)) == .alerts(kind: .hotel, watchID: 7))
        #expect(NotificationRouting.route(userInfo: ["route": "alerts"]) == .alerts(kind: nil, watchID: nil))
    }

    @Test func tripAndNearbyRoutes() {
        #expect(NotificationRouting.route(userInfo: ["route": "trip", "plan_id": "12"]) == .planDetail(id: 12))
        #expect(NotificationRouting.route(["route": "trip", "plan_id": "x"]) == .tab(.trips))
        #expect(NotificationRouting.route(["route": "nearby"]) == .nearby)
    }

    @Test func permissionRequestsOnlyOnCall() async {
        let center = FakeCenter()
        #expect(center.requests == 0)
        #expect(await NotificationPermission.request(center: center))
        #expect(center.requests == 1)
    }

    @Test func nextPollIsJitteredWithinFiveMinutes() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(BackgroundTasks.nextAlertPollDate(now: now, jitter: 9999).timeIntervalSince(now) == 2100)
        #expect(BackgroundTasks.nextAlertPollDate(now: now, jitter: -9999).timeIntervalSince(now) == 1500)
    }

    @Test func nearbyTemplateFills() {
        #expect(NearbyInvite.render(template: "{place}: {item} {minutes} min", place: "A", item: "B", minutes: 4) == "A: B 4 min")
    }
}
