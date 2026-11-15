import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureAlerts

@MainActor
final class InboxPushRowsSnapshotTests: XCTestCase {
    private func config(_ name: String, dark: Bool = false, height: CGFloat) -> SnapshotConfig {
        SnapshotConfig(name: name, device: .iPhoneSe(.portrait), dark: dark, canvas: CGSize(width: 320, height: height))
    }

    private func inbox(_ items: [AppNotification]) -> some View {
        let model = NotificationsModel(env: AppEnvironment.fake(), track: { _ in }, now: { fixedNow })
        model.show(items: items, unread: items.filter { $0.readAt == nil }.count)
        return NavigationStack { NotificationsInboxView(model: model) }
    }

    private func row(
        _ id: Int, _ kind: String, _ title: String, _ body: String, age: TimeInterval = 3600, read: Bool = false,
        data: JSONValue = .null
    ) -> AppNotification {
        AppNotification(
            id: id, kind: kind, title: title, body: body, data: data, createdAt: iso(fixedNow.addingTimeInterval(-age)),
            readAt: read ? iso(fixedNow) : nil)
    }

    private var tripRows: [AppNotification] {
        [
            row(1, "trip_t30", "Tokyo is 30 days away", "A good moment to check your documents, flights and hotel.", data: ["plan_id": 7]),
            row(2, "trip_t7", "7 days to Tokyo", "Time to pack.", age: 86_400 * 2, read: true, data: ["plan_id": 7]),
            row(3, "trip_morning", "Good morning from Tokyo", "Open Today for your plan.", age: 7200, data: ["plan_id": 7]),
            row(4, "weather_rain", "Rain at 3 pm", "Your Senso-ji visit may get wet.", age: 600, data: ["plan_id": 7]),
        ]
    }

    func test_inboxTripRows() async {
        await assertSnapshots(
            of: { self.inbox(self.tripRows) }, named: "InboxTripRows",
            configs: [config("se-light", height: 475), config("se-dark", dark: true, height: 475)], layout: .screen)
    }

    func test_inboxUnknownKind() async {
        let rows = [row(1, "brand_new_kind", "Something new from Voyager", "This app does not know this kind yet.")]
        await assertSnapshots(
            of: { self.inbox(rows) }, named: "InboxUnknownKind", configs: [config("se-light", height: 215)], layout: .screen)
    }

    func test_inboxGroupedDrop() async {
        let rows = [
            row(
                1, "fare_drop", "3 price drops", "Latest: Berlin to Lisbon, now $454",
                data: ["group_count": 3, "links": ["alerts": "/alerts"]])
        ]
        await assertSnapshots(
            of: { self.inbox(rows) }, named: "InboxGroupedDrop", configs: [config("se-light", height: 195)], layout: .screen)
    }
}
