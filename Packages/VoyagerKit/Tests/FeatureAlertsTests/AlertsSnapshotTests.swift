import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureAlerts

@MainActor
final class AlertsSnapshotTests: XCTestCase {
    private let configs: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 2600)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 2600)),
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 2000)),
        SnapshotConfig(
            name: "se-de-ax5", device: .iPhoneSe(.portrait), dark: false, language: .de,
            size: .accessibilityExtraExtraExtraLarge, canvas: CGSize(width: 320, height: 6000)),
    ]
    private let small: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 1400)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 1400)),
    ]

    private func model(_ rows: [WatchRow], focus: (WatchKind, Int)? = nil) -> AlertsModel {
        let model = AlertsModel(
            env: AppEnvironment.fake(), kind: focus?.0, watchID: focus?.1, track: { _ in }, now: { fixedNow })
        model.show(rows: rows)
        return model
    }

    private var sampleRows: [WatchRow] {
        var estimate = WatchRow(hotel(4))
        estimate.isEstimate = true
        return [
            WatchRow(fare(1, email: true)), WatchRow(fare(2, status: "paused", mode: "below_target", target: 400, flexible: 3)),
            estimate, WatchRow(activity(9)), WatchRow(fare(3, status: "expired")),
        ]
    }

    func test_list() async {
        await assertSnapshots(
            of: { NavigationStack { AlertsRootView(model: self.model(self.sampleRows)) } },
            named: "list", configs: configs, layout: .screen)
    }

    func test_focusedWatch() async {
        await assertSnapshots(
            of: { NavigationStack { AlertsRootView(model: self.model(self.sampleRows, focus: (.hotel, 4))) } },
            named: "focused", configs: small, layout: .screen)
    }

    func test_empty() async {
        await assertSnapshots(
            of: { NavigationStack { AlertsRootView(model: self.model([])) } }, named: "empty", configs: small,
            layout: .screen)
    }

    func test_editor() async {
        await assertSnapshots(
            of: { WatchEditor(row: WatchRow(fare(2, mode: "below_target", target: 400, flexible: 3)), hasEmail: true, onSave: { _ in }, onCancel: {}) },
            named: "editor", configs: small, layout: .screen)
    }

    func test_liveCheckResult() async {
        let result = LiveCheckResult(
            kind: .flight, watchId: 1, summary: "Fares from Berlin to Lisbon are around $440 on two sites today.",
            quotes: [LiveQuote(label: "Kayak", amount: 440, currency: "USD", sourceIndex: 0)],
            sources: [LiveSource(title: "Kayak", uri: "https://kayak.com/flights")], searchedFor: ["ber lis flight 1-8 dec"])
        let state = LiveCheckState(row: WatchRow(fare(1)), phase: .result(result))
        await assertSnapshots(
            of: { LiveCheckSheet(state: state, onDismiss: {}) }, named: "live-result", configs: small, layout: .screen)
    }

    func test_inbox() async {
        let items = [
            AppNotification(
                id: 1, kind: "fare_drop", title: "Berlin → Lisbon dropped to $454 (−$46)", body: "For 1–8 Dec",
                data: ["links": ["alerts": "/alerts?watch=1"]], createdAt: iso(fixedNow.addingTimeInterval(-3600))),
            AppNotification(
                id: 2, kind: "fare_drop", title: "Lumen Hotel dropped to €352", body: "Lisbon · 10–14 Dec",
                createdAt: iso(fixedNow.addingTimeInterval(-86_400 * 3)), readAt: iso(fixedNow)),
        ]
        let model = NotificationsModel(env: AppEnvironment.fake(), track: { _ in }, now: { fixedNow })
        model.show(items: items, unread: 1)
        await assertSnapshots(
            of: { NavigationStack { NotificationsInboxView(model: model) } }, named: "inbox", configs: small,
            layout: .screen)
    }
}
