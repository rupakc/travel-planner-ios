import Domain
import Foundation
import Testing
import TestSupport
import Telemetry
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

@MainActor
struct InboxPushRowsTests {
    private final class Events: @unchecked Sendable {
        var opens: [String] = []
        func record(_ event: TelemetryEvent) {
            if case .notifOpen(let category, let source) = event { opens.append("\(category):\(source)") }
        }
    }

    private func row(_ kind: String?, data: JSONValue = .null) -> AppNotification {
        AppNotification(id: 1, kind: kind, title: "Title", body: "Body", data: data, createdAt: iso(fixedNow.addingTimeInterval(-600)))
    }

    private func open(_ item: AppNotification, journey: Bool) async -> (routes: [Route], events: [String]) {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["journey": .bool(journey)]))
        let events = Events()
        let model = NotificationsModel(env: env, track: { events.record($0) }, now: { fixedNow })
        await model.open(item)
        return (env.recordedRoutes, events.opens)
    }

    @Test func test_tripRowTapOpensToday() async {
        let result = await open(row("trip_t7", data: ["plan_id": 12]), journey: true)
        #expect(result.routes == [.tripToday(planID: 12)])
        #expect(result.events == ["trip_reminders:inapp"])
    }

    @Test func test_tripRowFallsBackToTheTripDetailWithoutJourney() async {
        let result = await open(row("trip_morning", data: ["plan_id": 12]), journey: false)
        #expect(result.routes == [.planDetail(id: 12)])
    }

    @Test func test_emptyPlanIDOpensNothingNewInTheInbox() async {
        let cases: [JSONValue] = [.null, ["plan_id": .null], ["plan_id": 0]]
        for data in cases {
            #expect(await open(row("trip_t1", data: data), journey: true).routes.isEmpty)
        }
    }

    @Test func test_unknownKindIsAGenericRow() async {
        let result = await open(row("brand_new_kind", data: ["plan_id": 3]), journey: true)
        #expect(result.routes.isEmpty && result.events.isEmpty)
        #expect(NotificationRowIcon.symbol(for: row("brand_new_kind")) == "bell")
        #expect(NotificationRowIcon.symbol(for: row(nil)) == "bell")
    }

    @Test func test_priceRowsKeepTheirLookAndTheirWatch() async {
        #expect(NotificationRowIcon.symbol(for: row("fare_drop")) == nil)
        let result = await open(row("fare_drop", data: ["watch_id": 7]), journey: true)
        #expect(result.routes == [.alerts(kind: nil, watchID: 7)])
        #expect(result.events == ["price_drops:inapp"])
    }

    @Test func test_iconsByKind() {
        #expect(NotificationRowIcon.symbol(for: row("trip_t30")) == "calendar.badge.clock")
        #expect(NotificationRowIcon.symbol(for: row("trip_morning")) == "sun.max.fill")
        #expect(NotificationRowIcon.symbol(for: row("weather_rain")) == "cloud.sun.rain.fill")
        #expect(NotificationRowIcon.symbol(for: row("social_new_follower")) == "person.2.fill")
        #expect(NotificationRowIcon.symbol(for: row("fare_drop", data: ["group_count": 3])) == "square.stack.fill")
        #expect(NotificationRowIcon.symbol(for: row("fare_drop", data: ["group_count": 1])) == nil)
    }
}
