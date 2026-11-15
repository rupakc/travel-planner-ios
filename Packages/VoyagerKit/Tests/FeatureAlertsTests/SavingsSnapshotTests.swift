import SharedUI
import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureAlerts

@MainActor
final class SavingsSnapshotTests: XCTestCase {
    private func config(_ name: String, dark: Bool = false, height: CGFloat = 420) -> SnapshotConfig {
        SnapshotConfig(name: name, device: .iPhoneSe(.portrait), dark: dark, canvas: CGSize(width: 320, height: height))
    }

    private var savingsEnv: AppEnvironment {
        AppEnvironment.fake(
            clientConfig: ClientConfig(features: [
                "alerts_api": .number(2), "price_alerts_v2": .bool(true), "live_prices": .bool(true), "sharing": .number(1),
            ]))
    }

    private let milestone = Savings(
        totalUSD: 245, byCurrency: ["EUR": 12, "GBP": 9], dropsCaught: 4, targetsHit: 1, watchesActive: 3,
        best: SavingsBest(kind: .hotel, watchId: 4, title: "Lumen Hotel", caught: 46, currency: "EUR"),
        nextMilestone: 1000, progressPct: 24)

    private func header(_ savings: Savings) -> some View {
        let model = AlertsHeaderModel(env: savingsEnv)
        model.show(savings)
        return SavingsHeader(model: model)
    }

    func test_savingsHeaderMilestone() async {
        let light = config("se-light", height: 560)
        let dark = config("se-dark", dark: true, height: 560)
        await assertSnapshots(
            of: { self.header(self.milestone) }, named: "SavingsHeaderMilestone", configs: [light, dark], layout: .component)
    }

    func test_savingsHeaderEmpty() async {
        await assertSnapshots(
            of: { self.header(Savings()) }, named: "SavingsHeaderEmpty", configs: [config("se-light", height: 200)],
            layout: .component)
    }

    func test_savingsHeaderGermanAX5() async {
        let cfg = SnapshotConfig(
            name: "se-de-ax5", device: .iPhoneSe(.portrait), dark: false, language: .de,
            size: .accessibilityExtraExtraExtraLarge, canvas: CGSize(width: 320, height: 2400))
        await assertSnapshots(of: { self.header(self.milestone) }, named: "SavingsHeaderAX5", configs: [cfg], layout: .component)
    }

    func test_pausedBanner() async {
        await assertSnapshots(
            of: { PausedBanner() }, named: "PausedBanner",
            configs: [config("se-light", height: 200), config("se-dark", dark: true, height: 200)], layout: .component)
    }

    // MARK: Inbox rows

    private let dropGame: JSONValue = [
        "xp": 340, "awards": [["rule": "price_drop", "points": 15], ["rule": "target", "points": 10]],
        "badges": [["id": "first_trip", "earned_at": "2026-11-14T10:00:00Z"]],
    ]

    private func dropRow(target: Bool, currency: String, title: String, game: Bool) -> AppNotification {
        var data: [String: JSONValue] = [
            "drop": [
                "from": 500, "to": 454, "amount": 46, "pct": 9.2, "currency": .string(currency), "target_hit": .bool(target),
                "observed": true,
            ],
            "watch_kind": "flight", "title": .string(title), "links": ["alerts": "/alerts?watch=1"],
        ]
        if game { data["game"] = dropGame }
        return AppNotification(
            id: 1, kind: "fare_drop", title: target ? "Lumen Hotel reached your target" : "Berlin → Lisbon dropped to $454",
            body: "For 1–8 Dec", data: .object(data), createdAt: iso(fixedNow.addingTimeInterval(-3600)))
    }

    private func inbox(_ items: [AppNotification], game: StaticGameVisibility) -> some View {
        let model = NotificationsModel(
            env: savingsEnv, track: { _ in }, now: { fixedNow }, gameVisibility: { game })
        model.show(items: items, unread: items.count)
        return NavigationStack { NotificationsInboxView(model: model) }
    }

    func test_dropMomentLight() async {
        let row = dropRow(target: false, currency: "USD", title: "Berlin → Lisbon", game: true)
        await assertSnapshots(
            of: { self.inbox([row], game: .visible) }, named: "DropMomentLight",
            configs: [config("se-light", height: 560)], layout: .screen)
    }

    func test_dropTargetHitDark() async {
        let row = dropRow(target: true, currency: "EUR", title: "Lumen Hotel", game: true)
        await assertSnapshots(
            of: { self.inbox([row], game: .visible) }, named: "DropTargetHitDark",
            configs: [config("se-dark", dark: true, height: 560)], layout: .screen)
    }

    func test_dropGameLineHidden() async {
        let row = dropRow(target: false, currency: "USD", title: "Berlin → Lisbon", game: true)
        await assertSnapshots(
            of: { self.inbox([row], game: .hidden) }, named: "DropGameLineHidden",
            configs: [config("se-light", height: 560)], layout: .screen)
    }

    func test_digestRowHindi() async {
        let digest = AppNotification(
            id: 2, kind: "price_digest", title: "आपका साप्ताहिक डाइजेस्ट", body: "इस सप्ताह आपकी निगरानी सूची कैसे बदली।",
            data: [
                "digest": [
                    "week": "2026-W46",
                    "watches": [
                        ["kind": "hotel", "watch_id": 4, "title": "Lumen Hotel, Lisbon", "latest": 352, "change_7d": -12.5,
                         "lowest": 340, "currency": "EUR"],
                        ["kind": "flight", "watch_id": 1, "title": "Berlin → Lisbon", "latest": 454, "change_7d": 8,
                         "lowest": 441, "currency": "USD"],
                    ],
                    "savings": ["total_usd": 245, "drops_caught": 4],
                ]
            ], createdAt: iso(fixedNow.addingTimeInterval(-86_400)))
        let cfg = SnapshotConfig(
            name: "se-hi", device: .iPhoneSe(.portrait), dark: false, language: .hi, canvas: CGSize(width: 320, height: 620))
        await assertSnapshots(
            of: { self.inbox([digest], game: .visible) }, named: "DigestRowHI", configs: [cfg], layout: .screen)
    }
}
