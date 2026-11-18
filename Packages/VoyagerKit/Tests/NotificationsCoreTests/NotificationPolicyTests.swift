import Foundation
import Testing
import VoyagerModel

@testable import NotificationsCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ iso: String) -> Date {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
}

private func trip(_ id: Int, from: String, to: String) -> PlanSummary {
    PlanSummary(
        id: id, name: "x",
        searchData: .object(["destination": "Tokyo", "departure_date": .string(from), "return_date": .string(to)]))
}

private let copy = TripReminderScheduler.Text(
    t30Title: { "t30 \($0)" }, t30Body: { "b30" }, t7Title: { "t7 \($0)" }, t7Body: { "b7" }, t1Title: { "t1 \($0)" },
    t1Body: { "b1" }, dayTitle: { "d\($0) \($1)" }, dayBody: { "bd" }, lastDayTitle: { "last \($0)" }, lastDayBody: { "bl" })

@Suite struct PushPayloadTests {
    @Test func test_groupedPushTitleFromServer() {
        let push = PushPayload(userInfo: [
            "aps": ["alert": ["title": "3 price drops", "body": "Latest: Berlin to Lisbon"], "sound": "default"],
            "kind": "fare_drop", "group_count": "3", "notification_id": NSNumber(value: 41),
        ])
        #expect(push.title == "3 price drops" && push.body == "Latest: Berlin to Lisbon")
        #expect(push.groupCount == 3 && push.notificationID == 41 && push.category == .priceDrops)
    }

    @Test func test_fakeApnsPayloadRoutes() {
        let info: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Tokyo in 7 days", "body": "Time to pack."], "sound": "default"],
            "category": "trip_reminders", "kind": "trip_t7", "plan_id": NSNumber(value: 42), "notification_id": 9,
            "link": "/trips/42/today",
        ]
        let push = PushPayload(userInfo: info)
        #expect(push.kind == "trip_t7" && push.category == .tripReminders && push.planID == 42 && push.notificationID == 9)
        #expect(NotificationRouting.route(userInfo: info, todayAvailable: true) == .tripToday(planID: 42))
        #expect(NotificationRouting.route(userInfo: info, todayAvailable: false) == .planDetail(id: 42))
    }

    @Test func test_tripTapOpensToday() {
        for kind in ["trip_t30", "trip_t7", "trip_t1", "trip_morning", "weather_rain"] {
            #expect(NotificationRouting.route(userInfo: ["kind": kind, "plan_id": "5"]) == .tripToday(planID: 5))
        }
    }

    @Test func test_emptyPlanIDOpensInbox() {
        #expect(NotificationRouting.route(userInfo: ["kind": "trip_t1", "plan_id": ""]) == .notifications)
        #expect(NotificationRouting.route(userInfo: ["kind": "trip_t1"]) == .notifications)
        #expect(NotificationRouting.route(userInfo: ["kind": "trip_t1", "plan_id": "0"]) == .notifications)
    }

    @Test func test_unknownKindOpensTheInbox() {
        #expect(NotificationRouting.route(userInfo: ["kind": "brand_new_kind", "plan_id": "5"]) == .notifications)
        #expect(PushPayload(userInfo: ["kind": "brand_new_kind"]).kind == nil)
    }

    @Test func test_unresolvedSocialLinkOpensIdeas() {
        // No link, or one the allow-list rejects: the Ideas tab, never the raw link.
        #expect(NotificationRouting.route(userInfo: ["kind": "social_new_follower"]) == .ideas)
        #expect(NotificationRouting.route(userInfo: ["kind": "social_idea_saved", "link": "https://evil.example/x"]) == .ideas)
    }

    @Test func test_priceTapStillOpensTheWatch() {
        let info: [AnyHashable: Any] = ["kind": "flight", "watch_id": "7", "category": "price_drops"]
        #expect(NotificationRouting.route(userInfo: info) == .alerts(kind: .flight, watchID: 7))
    }

    @Test func test_badFieldsAreDropped() {
        let push = PushPayload(userInfo: ["plan_id": "-3", "notification_id": 1.5, "group_count": "x", "category": "nope"])
        #expect(push.planID == nil && push.notificationID == nil && push.groupCount == nil && push.category == nil)
    }
}

@Suite struct PushGateTests {
    @Test func test_gate_registersOnlyWhenApnsAndAllowed() {
        let apns = RemoteFeatures(notificationsAPI: 1, notificationsV2: true, apns: true)
        let noApns = RemoteFeatures(notificationsAPI: 1, notificationsV2: true, apns: false)
        #expect(PushGate.shouldRegister(features: apns, permission: .allowed))
        for permission in [NotificationPermissionState.denied, .notDetermined, .unknown] {
            #expect(!PushGate.shouldRegister(features: apns, permission: permission))
        }
        #expect(!PushGate.shouldRegister(features: noApns, permission: .allowed))
        #expect(!PushGate.shouldRegister(config: nil, permission: .allowed))
        #expect(PushGate.shouldRegister(config: ClientConfig(features: ["apns": .bool(true)]), permission: .allowed))
    }
}

@Suite struct ReminderPolicyTests {
    private let plans = [trip(1, from: "2027-06-20", to: "2027-06-22")]
    private let now = day("2027-01-01")

    private func ids(_ policy: ReminderPolicy, catalog: NotificationCatalog? = nil) -> Set<String> {
        Set(TripReminderScheduler.reminders(
            for: plans, now: now, calendar: utc, text: copy, policy: policy, catalog: catalog).map(\.id))
    }

    @Test func test_localTripRemindersDroppedWhenServerPushLive() {
        let features = RemoteFeatures(notificationsAPI: 1, notificationsV2: true, apns: true)
        let policy = ReminderPolicy(features: features, settings: NotificationSettings(devices: 1))
        #expect(policy.serverPushLive)
        #expect(ids(policy) == ["trip-1-last"])
    }

    @Test func test_localRemindersKeptWithoutApns() {
        let features = RemoteFeatures(notificationsAPI: 1, notificationsV2: true, apns: false)
        let policy = ReminderPolicy(features: features, settings: NotificationSettings(devices: 1))
        #expect(!policy.serverPushLive)
        #expect(ids(policy) == ["trip-1-t30", "trip-1-t7", "trip-1-t1", "trip-1-day1", "trip-1-day2", "trip-1-last"])
    }

    @Test func test_pushLiveNeedsARegisteredDevice() {
        let features = RemoteFeatures(notificationsAPI: 1, notificationsV2: true, apns: true)
        #expect(!ReminderPolicy(features: features, settings: NotificationSettings(devices: 0)).serverPushLive)
        #expect(!ReminderPolicy(features: features, settings: nil).serverPushLive)
    }

    @Test func test_categorySwitchesGateLocalReminders() {
        let tripOff = ReminderPolicy(tripRemindersOn: false)
        #expect(ids(tripOff) == ["trip-1-day1", "trip-1-day2"])
        let morningOff = ReminderPolicy(morningBriefOn: false)
        #expect(ids(morningOff) == ["trip-1-t30", "trip-1-t7", "trip-1-t1", "trip-1-last"])
    }

    @Test func test_catalogCopyUsedOnlyWhenEveryPlaceholderFills() {
        let catalog = NotificationCatalog(locale: "es", templates: [
            "trip_t30": "{destination} en {days} dias", "trip_t7": "{days} dias, {unknown}",
        ])
        let items = TripReminderScheduler.reminders(
            for: plans, now: now, calendar: utc, text: copy, policy: ReminderPolicy(), catalog: catalog)
        let body = { (id: String) in items.first { $0.id == id }?.body }
        #expect(body("trip-1-t30") == "Tokyo en 30 dias")
        #expect(body("trip-1-t7") == "b7")  // `{unknown}` cannot be filled: the app's own copy
        #expect(body("trip-1-t1") == "b1")  // no template at all
    }

    @Test func test_capAt60StillHolds() {
        let many = (1...12).map { trip($0, from: "2027-06-\(String(format: "%02d", $0 + 10))", to: "2027-07-12") }
        let items = TripReminderScheduler.reminders(for: many, now: now, calendar: utc, text: copy)
        #expect(items.count == TripReminderScheduler.maxPending)
        #expect(items.contains { $0.id.hasSuffix("-t30") })
    }
}

@Suite struct PollerPolicyTests {
    private func defaults() -> UserDefaults {
        let name = "poller-policy-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    /// 2026-11-12T18:00Z is 23:30 in Kolkata, inside 22:00-07:00.
    private let night = ISO8601DateFormatter().date(from: "2026-11-12T18:00:00Z")!
    private let noon = ISO8601DateFormatter().date(from: "2026-11-12T08:00:00Z")!

    private func settings(
        off: [NotificationCategory] = [], cap: Int = 3, quiet: Bool = true, devices: Int = 0
    ) -> NotificationSettings {
        var categories: [NotificationCategory: Bool] = [:]
        for category in off { categories[category] = false }
        return NotificationSettings(
            categories: categories, quietHours: QuietHoursPref(enabled: quiet, start: "22:00", end: "07:00"), dailyCap: cap,
            timezone: "Asia/Kolkata", devices: devices)
    }

    private func poller(
        _ repo: FakeNotifications, _ center: FakeCenter, _ store: UserDefaults, at now: Date, context: PollContext?
    ) -> AlertPoller {
        AlertPoller(repo: repo, userID: "ann", center: center, defaults: store, context: { context }, now: { now })
    }

    private func row(_ id: Int, _ kind: String, age: TimeInterval = 7200, now: Date) -> AppNotification {
        AppNotification(
            id: id, kind: kind, title: "t\(id)", body: "b",
            createdAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-age)))
    }

    @Test func test_pollerHoldsDuringQuietHours() async {
        let repo = FakeNotifications()
        repo.items = [row(1, "trip_t7", now: night)]
        let center = FakeCenter()
        let store = defaults()
        let poll = poller(repo, center, store, at: night, context: PollContext(settings: settings()))
        #expect(await poll.poll() == 1)
        let held = center.added.first { $0.id == "alert-1" }
        #expect(held?.fireComponents != nil, "a held row is scheduled for the end of the window, not shown now")
        #expect(await poll.poll() == 0)
    }

    @Test func test_pollerDeliversNowOutsideQuietHours() async {
        let repo = FakeNotifications()
        repo.items = [row(1, "trip_t7", now: noon)]
        let center = FakeCenter()
        let poll = poller(repo, center, defaults(), at: noon, context: PollContext(settings: settings()))
        #expect(await poll.poll() == 1)
        #expect(center.added.first?.fireComponents == nil)
    }

    @Test func test_pollerRespectsCategoryOff() async {
        let repo = FakeNotifications()
        repo.items = [row(1, "fare_drop", now: noon), row(2, "trip_t1", now: noon)]
        let center = FakeCenter()
        let off = settings(off: [.priceDrops])
        let poll = poller(repo, center, defaults(), at: noon, context: PollContext(settings: off))
        #expect(await poll.poll() == 1)
        #expect(Set(center.added.map(\.id)) == ["alert-2"])
        #expect(await poll.poll() == 0, "the dropped row is marked seen, not retried")
    }

    @Test func test_pollerAppliesTheDailyCapToNonPriceRows() async {
        let repo = FakeNotifications()
        repo.items = [row(1, "trip_t7", now: noon), row(2, "trip_t1", now: noon), row(3, "trip_morning", now: noon)]
        let center = FakeCenter()
        let poll = poller(repo, center, defaults(), at: noon, context: PollContext(settings: settings(cap: 2)))
        #expect(await poll.poll() == 2)
    }

    @Test func test_pollerWithoutSettingsKeepsTheLegacyBehaviour() async {
        let repo = FakeNotifications()
        repo.items = [AppNotification(id: 1, title: "Drop"), row(2, "brand_new_kind", now: noon)]
        let center = FakeCenter()
        let poll = poller(repo, center, defaults(), at: noon, context: PollContext())
        #expect(await poll.poll() == 2)
    }

    @Test func test_pollerWaitsWhenTheRulesCannotBeRead() async {
        let repo = FakeNotifications()
        repo.items = [row(1, "fare_drop", now: noon)]
        let center = FakeCenter()
        let store = defaults()
        #expect(await poller(repo, center, store, at: noon, context: nil).poll() == 0)
        #expect(await poller(repo, center, store, at: noon, context: PollContext()).poll() == 1)
    }

    @Test func test_pushAndPollDedupe() async {
        let repo = FakeNotifications()
        repo.items = [row(1, "fare_drop", now: noon), row(2, "fare_drop", now: noon), row(3, "fare_drop", now: noon)]
        let center = FakeCenter()
        let store = defaults()
        // Row 1 arrived as a push the app saw; row 2 is in the notification list (delivered while the app was closed).
        AlertPoller.recordPush(id: 1, userID: "ann", defaults: store)
        center.deliveredIDs = [2]
        let live = PollContext(settings: settings(devices: 1), serverPushLive: true)
        let poll = poller(repo, center, store, at: noon, context: live)
        #expect(await poll.poll() == 1, "row 3 is two hours old and was never delivered: the safety net shows it")
        #expect(Set(center.added.map(\.id)) == ["alert-3"])
    }

    @Test func test_safetyNetLeavesYoungRowsForThePush() async {
        let repo = FakeNotifications()
        repo.items = [row(1, "fare_drop", age: 60, now: noon)]
        let center = FakeCenter()
        let live = PollContext(settings: settings(devices: 1), serverPushLive: true)
        let poll = poller(repo, center, defaults(), at: noon, context: live)
        #expect(await poll.poll() == 0)
        #expect(center.added.isEmpty)
        // An hour later the push never came: the row is shown.
        let later = poller(repo, center, defaults(), at: noon.addingTimeInterval(3600), context: live)
        #expect(await later.poll() == 1)
    }

    // M7: one source per trip reminder.
    @Test func test_tripRowsAreNotShownWhenThePhoneSchedulesTheReminders() async {
        let repo = FakeNotifications()
        repo.items = [
            row(1, "trip_t30", now: noon), row(2, "trip_t7", now: noon), row(3, "trip_t1", now: noon),
            row(4, "trip_morning", now: noon), row(5, "weather_alert", now: noon), row(6, "social_new_follower", now: noon),
        ]
        let center = FakeCenter()
        let store = defaults()
        let rules = PollContext(settings: settings(quiet: false), localTripReminders: true)
        let poll = poller(repo, center, store, at: noon, context: rules)
        #expect(await poll.poll() == 2)
        #expect(Set(center.added.map(\.id)) == ["alert-5", "alert-6"], "weather and social have no local twin")
        #expect(await poll.poll() == 0, "the skipped trip rows are marked seen, not retried")
    }

    @Test func test_tripRowsStillShownWhenNoLocalReminderOwnsThem() async {
        let repo = FakeNotifications()
        repo.items = [row(1, "trip_t7", now: noon), row(2, "trip_morning", now: noon)]
        let center = FakeCenter()
        let poll = poller(repo, center, defaults(), at: noon, context: PollContext(settings: settings(quiet: false)))
        #expect(await poll.poll() == 2)
    }

    // M6: a tap routes by the row's kind, not always to Alerts.
    @Test func test_polledNonPriceRowsRouteByKind() {
        func info(_ kind: String, _ data: JSONValue = .null) -> [String: String] {
            AlertPoller.userInfo(AppNotification(id: 9, kind: kind, title: "t", data: data))
        }
        let trip = info("trip_t7", .object(["link": "/trips/42"]))
        #expect(trip["route"] == nil && trip["plan_id"] == "42" && trip["kind"] == "trip_t7" && trip["notification_id"] == "9")
        #expect(NotificationRouting.route(userInfo: trip) == .tripToday(planID: 42))
        #expect(NotificationRouting.route(userInfo: info("weather_alert", .object(["plan_id": 7]))) == .tripToday(planID: 7))
        #expect(NotificationRouting.route(userInfo: info("social_new_follower")) == .ideas)
        #expect(NotificationRouting.route(userInfo: info("quiz_daily")) == .play)
        #expect(NotificationRouting.route(userInfo: info("trip_t1")) == .notifications, "no plan id: the inbox")
    }

    @Test func test_polledPriceRowsStillOpenAlerts() {
        let item = AppNotification(id: 3, kind: "fare_drop", title: "t", data: .object(["kind": "flight", "watch_id": 5]))
        #expect(NotificationRouting.route(userInfo: AlertPoller.userInfo(item)) == .alerts(kind: .flight, watchID: 5))
    }

    @MainActor @Test func test_notifOpenCategoryFollowsTheRowKind() {
        func category(_ kind: String) -> NotificationCategory? {
            let info: [AnyHashable: Any] = AlertPoller.userInfo(AppNotification(id: 1, kind: kind, title: "t"))
            return NotificationTapDelegate.openedCategory(info: info, push: PushPayload(userInfo: info))
        }
        #expect(category("trip_t7") == .tripReminders)
        #expect(category("trip_morning") == .morningBrief)
        #expect(category("social_idea_saved") == .social)
        #expect(category("quiz_daily") == .quiz)
        #expect(category("weather_alert") == .weather)
        #expect(category("fare_drop") == .priceDrops)
    }
}
