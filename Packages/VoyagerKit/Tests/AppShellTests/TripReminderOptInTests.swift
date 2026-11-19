import Foundation
import NotificationsCore
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import AppShell

private final class MemoryCenter: NotificationCenterClient, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: LocalNotification] = [:]
    var ids: Set<String> { lock.withLock { Set(items.keys) } }
    func requestAuthorization() async -> Bool { true }
    func isAuthorized() async -> Bool { true }
    @discardableResult
    func add(_ notification: LocalNotification) async -> Bool {
        lock.withLock { items[notification.id] = notification }
        return true
    }
    func pendingIdentifiers() async -> [String] { Array(ids) }
    func removePending(identifiers: [String]) async { lock.withLock { for id in identifiers { items[id] = nil } } }
    func purge(prefixes: [String]) async {
        lock.withLock { items = items.filter { entry in !prefixes.contains { entry.key.hasPrefix($0) } } }
    }
}

/// M8: the Settings "Trip reminders" switch gates the local reminders.
@MainActor @Suite struct TripReminderOptInTests {
    private func env() -> AppEnvironment {
        let fakes = FakeRepositories()
        fakes.plans.onList.returns([
            PlanSummary(
                id: 1, name: "x",
                searchData: .object(["destination": "Tokyo", "departure_date": "2099-03-20", "return_date": "2099-03-23"]))
        ])
        return AppEnvironment.fake(fakes: fakes)
    }

    @Test func test_switchOffSchedulesNothingAndClearsPending() async {
        let env = env()
        let center = MemoryCenter()
        await center.add(LocalNotification(id: "trip-1-t7", title: "old", body: ""))
        await center.add(LocalNotification(id: "alert-5", title: "keep", body: ""))
        env.device.reminderOptIn = false
        await TripReminderScheduler.refresh(env: env, center: center)
        #expect(center.ids == ["alert-5"])
    }

    @Test func test_switchOnSchedulesAndTurningItOffCancels() async {
        let env = env()
        let center = MemoryCenter()
        env.device.reminderOptIn = true
        await TripReminderScheduler.refresh(env: env, center: center)
        #expect(center.ids.contains("trip-1-t7"))
        env.device.reminderOptIn = false
        await TripReminderScheduler.refresh(env: env, center: center)
        #expect(center.ids.isEmpty)
    }

    @Test func test_refreshStopsWhenTheAccountChangedDuringIt() async {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes)
        fakes.plans.onList.handler = { _ in
            // The user signs out while the plans are being read.
            await env.auth.signOut()
            return [
                PlanSummary(
                    id: 1, name: "x",
                    searchData: .object([
                        "destination": "Tokyo", "departure_date": "2099-03-20", "return_date": "2099-03-23",
                    ]))
            ]
        }
        let center = MemoryCenter()
        env.device.reminderOptIn = true
        await TripReminderScheduler.refresh(env: env, center: center)
        #expect(center.ids.isEmpty, "the previous account's reminders must not come back")
    }
}
