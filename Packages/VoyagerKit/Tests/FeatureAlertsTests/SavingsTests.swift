import Foundation
import L10n
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

@MainActor
struct SavingsTests {
    private func config(
        alertsAPI: Int = 2, live: Bool? = true, sharing: Int = 0, game: Bool = true
    ) -> ClientConfig {
        var features: [String: JSONValue] = [
            "alerts_api": .number(Double(alertsAPI)), "price_alerts_v2": .bool(true), "sharing": .number(Double(sharing)),
            "game": .bool(game),
        ]
        if let live { features["live_prices"] = .bool(live) }
        return ClientConfig(features: features)
    }

    private func header(
        _ clientConfig: ClientConfig? = nil, configure: (FakeRepositories) -> Void = { _ in }
    ) -> (AlertsHeaderModel, AppEnvironment, FakeRepositories) {
        let fakes = FakeRepositories()
        configure(fakes)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: clientConfig ?? config())
        return (AlertsHeaderModel(env: env), env, fakes)
    }

    private final class Events {
        var drops: [String] = []
        var digests: [String] = []
        func record(_ event: TelemetryEvent) {
            switch event {
            case .alertDropSeen(let kind, let hit, let via): drops.append("\(kind):\(hit):\(via)")
            case .alertDigestOpen(let via): digests.append(via)
            default: break
            }
        }
    }

    private let sample = Savings(
        totalUSD: 245, byCurrency: ["EUR": 12], dropsCaught: 4, targetsHit: 1, watchesActive: 3,
        best: SavingsBest(kind: .hotel, watchId: 4, title: "Lumen Hotel", caught: 46, currency: "EUR"),
        nextMilestone: 1000, progressPct: 24)

    // MARK: Wording

    /// The words for "you saved" in each language; none may appear in any drop or savings copy.
    private static let bannedByLanguage: [AppLanguage: [String]] = [
        .en: ["saved", "saving", "you save"], .es: ["ahorr"], .de: ["gespart", "sparen", "spart"], .fr: ["économis", "epargn", "épargn"],
        .hi: ["बचत", "बचा"], .zh: ["节省", "省了", "省下"], .bn: ["সাশ্রয", "বাঁচ", "বাচ"],
    ]

    @Test func test_neverSaysSaved() {
        for language in AppLanguage.allCases {
            LanguageController.withLanguage(language) {
                var strings: [String] = [
                    L10n.text(K.savings.title), L10n.text(K.savings.amountLine, ["amount": "$1"]),
                    L10n.text(K.savings.best, ["title": "T", "amount": "$1"]), L10n.text(K.savings.bestNoTitle, ["amount": "$1"]),
                    L10n.text(K.savings.caveat), L10n.text(K.savings.empty), L10n.text(K.savings.emptyHint),
                    L10n.text(K.savings.drops, count: 1), L10n.text(K.savings.drops, count: 3),
                    L10n.text(K.savings.targets, count: 1), L10n.text(K.savings.targets, count: 3),
                    L10n.text(K.savings.otherCurrencies), L10n.text(K.savings.progress, ["pct": "9", "amount": "$1"]),
                    L10n.text(K.savings.allDone), L10n.text(K.savings.milestones),
                    L10n.text(K.savings.milestoneReached, ["amount": "$1"]), L10n.text(K.savings.milestoneAhead, ["amount": "$1"]),
                    L10n.text(K.savings.share), L10n.text(K.savings.card.headline, ["amount": "$1"]),
                    L10n.text(K.savings.card.headlineOther), L10n.text(K.savings.card.footer),
                    L10n.text(K.dropMoment.title), L10n.text(K.dropMoment.titleTarget),
                    L10n.text(K.dropMoment.caught, ["amount": "$1", "percent": "9%"]), L10n.text(K.dropMoment.nowPrice),
                    L10n.text(K.dropMoment.xp, ["xp": "5"]), L10n.text(K.dropMoment.note), L10n.text(K.dropMoment.story),
                    L10n.text(K.dropMoment.badge, ["name": "N"]),
                    L10n.text(K.alertsHub.paused.title), L10n.text(K.alertsHub.paused.body),
                    L10n.text(K.alertsHub.digest.title), L10n.text(K.alertsHub.digest.body),
                ]
                let drop = DropData(from: 500, to: 454, amount: 46, pct: 9.2, currency: "USD", targetHit: true)
                let content = DropMomentContent(drop: drop, game: nil, showsGame: false)
                strings += [content.heading, content.spoken, content.note]
                for text in strings {
                    #expect(!text.isEmpty && !text.contains("{{"), "\(language): empty or unfilled copy")
                    for word in Self.bannedByLanguage[language] ?? [] {
                        #expect(!text.lowercased().contains(word), "\(language) says \"\(word)\" in: \(text)")
                    }
                }
            }
        }
    }

    // MARK: Savings tally

    @Test func test_milestoneProgress() {
        LanguageController.withLanguage(.en) {
            #expect(SavingsText.progressText(sample) == "24% of the way to $1,000")
            #expect(SavingsText.progressFraction(sample) == 0.24)
            var done = sample
            done.totalUSD = 1500
            done.nextMilestone = nil
            done.progressPct = 100
            #expect(SavingsText.progressText(done) == "Every milestone reached")
            #expect(SavingsText.progressFraction(done) == 1)
            var wild = sample
            wild.progressPct = 140
            #expect(SavingsText.progressFraction(wild) == 1)
            wild.progressPct = -5
            #expect(SavingsText.progressFraction(wild) == 0)
            let chips = SavingsText.milestoneChips(sample)
            #expect(chips.map(\.amount) == [50, 200, 1000])
            #expect(chips.map(\.reached) == [true, true, false])
            #expect(chips[0].text == "$50 reached" && chips[2].text == "$1,000 ahead")
            // A total of exactly a milestone has passed it.
            var exact = sample
            exact.totalUSD = 50
            #expect(SavingsText.milestoneChips(exact).first?.reached == true)
        }
    }

    @Test func test_byCurrencyNotConverted() {
        LanguageController.withLanguage(.en) {
            #expect(SavingsText.totalLine(sample) == "Drops caught: $245.00")
            #expect(SavingsText.currencyLines(sample) == ["€12.00"])
            #expect(SavingsText.bestText(sample) == "Best catch: Lumen Hotel, €46.00")
            var onlyEuro = sample
            onlyEuro.totalUSD = 0
            #expect(SavingsText.totalLine(onlyEuro) == nil)
            #expect(!onlyEuro.isEmpty)
            #expect(SavingsText.countsLine(sample) == "4 drops caught · 1 target hit")
            var two = sample
            two.byCurrency = ["GBP": 9, "EUR": 12]
            #expect(SavingsText.currencyLines(two) == ["€12.00", "£9.00"])
        }
    }

    @Test func test_summaryLoadsAndEmptyIsEmpty() async {
        let (model, _, fakes) = header { $0.alertsV2.onSummary.returns(self.sample) }
        await model.load()
        #expect(model.savings == sample)
        #expect(fakes.alertsV2.onSummary.callCount == 1)
        let (emptyModel, _, _) = header { $0.alertsV2.onSummary.returns(Savings()) }
        await emptyModel.load()
        #expect(emptyModel.savings?.isEmpty == true)
    }

    @Test func test_summaryNotCalledOnOlderBackend() async {
        let (model, _, fakes) = header(config(alertsAPI: 1))
        await model.load()
        #expect(model.phase == .unavailable)
        #expect(fakes.alertsV2.onSummary.callCount == 0)
        #expect(!model.isAvailable && !model.showsPausedBanner)
    }

    @Test func test_summaryFailureThenRetry() async {
        let (model, _, fakes) = header { $0.alertsV2.onSummary.fails(APIError.network) }
        await model.load()
        guard case .failed(let message) = model.phase else {
            Issue.record("expected failed")
            return
        }
        #expect(!message.isEmpty)
        fakes.alertsV2.onSummary.returns(sample)
        await model.load()
        #expect(model.savings == sample)
        // A later failed refresh keeps the tally on screen.
        fakes.alertsV2.onSummary.fails(APIError.network)
        await model.load()
        #expect(model.savings == sample)
    }

    @Test func test_shareSavingsOnlyWithSharingAndSomethingCaught() async {
        let (off, offEnv, _) = header(config(sharing: 0)) { $0.alertsV2.onSummary.returns(self.sample) }
        await off.load()
        #expect(!off.canShare)
        off.shareSavings()
        #expect(offEnv.recordedRoutes.isEmpty)
        let (on, onEnv, _) = header(config(sharing: 1)) { $0.alertsV2.onSummary.returns(self.sample) }
        await on.load()
        #expect(on.canShare)
        on.shareSavings()
        #expect(onEnv.recordedRoutes == [.shareSheet(.savings)])
        let (empty, _, _) = header(config(sharing: 1)) { $0.alertsV2.onSummary.returns(Savings()) }
        await empty.load()
        #expect(!empty.canShare)
    }

    // MARK: Paused banner

    @Test func test_pausedBannerFollowsFlag() {
        #expect(header(config(live: false)).0.showsPausedBanner)
        #expect(!header(config(live: true)).0.showsPausedBanner)
        // An older backend that never sent the flag is not "paused".
        #expect(!header(config(live: nil)).0.showsPausedBanner)
        // No Alerts 2.0: no banner either.
        #expect(!header(config(alertsAPI: 0, live: false)).0.showsPausedBanner)
    }

    // MARK: Drop moment

    private func dropNote(id: Int = 1, data: JSONValue) -> AppNotification {
        AppNotification(id: id, kind: "fare_drop", title: "Berlin → Lisbon dropped to $454", data: data)
    }

    private let dropData: JSONValue = [
        "drop": ["from": 500, "to": 454, "amount": 46, "pct": 9.2, "currency": "USD", "target_hit": false, "observed": true],
        "game": [
            "xp": 340, "awards": [["rule": "price_drop", "points": 15], ["rule": "target", "points": 10]],
            "badges": [["id": "deal_hunter_1", "earned_at": "2026-11-14T10:00:00Z"]],
        ],
        "watch_kind": "hotel", "title": "Lumen Hotel",
    ]

    @Test func test_dropCardCopyAndTargetVariant() {
        LanguageController.withLanguage(.en) {
            let drop = DropData(from: 500, to: 454, amount: 46, pct: 9.2, currency: "USD", targetHit: false)
            let plain = DropMomentContent(drop: drop, game: nil, showsGame: true)
            #expect(plain.heading == "Price drop caught")
            #expect(plain.amountText == "−$46.00" && plain.percentText == "−9%")
            #expect(plain.spoken == "Caught a drop of $46.00 (9%)")
            #expect(plain.fromText == "$500.00" && plain.toText == "$454.00")
            let hit = DropMomentContent(
                drop: DropData(from: 500, to: 454, amount: 46, pct: 9.2, currency: "EUR", targetHit: true), game: nil, showsGame: true)
            #expect(hit.heading == "Your target price is here" && hit.targetHit)
            #expect(hit.amountText == "−€46.00")
        }
    }

    @Test func test_gameLineHiddenWhenHideGame() {
        LanguageController.withLanguage(.en) {
            let note = dropNote(data: dropData)
            guard let drop = note.dropData else {
                Issue.record("no drop")
                return
            }
            let game = note.gameDelta
            #expect(game?.awardedPoints == 25)
            let shown = DropMomentContent(drop: drop, game: game, showsGame: true)
            // The notification's own award (15 + 10), never the running total (340).
            #expect(shown.xpText == "+25 XP")
            #expect(shown.badgeTexts.count == 1 && shown.badgeTexts[0].hasPrefix("Badge earned: "))
            let hidden = DropMomentContent(drop: drop, game: game, showsGame: false)
            #expect(hidden.xpText == nil && hidden.badgeTexts.isEmpty)
        }
    }

    @Test func test_gameVisibilityRules() {
        let (_, env, _) = header()
        let track: @MainActor (TelemetryEvent) -> Void = { _ in }
        // The account's hide_game cannot be read yet: unreadable counts as hidden.
        #expect(!InboxExtras(env: env, track: track).showsGame)
        #expect(InboxExtras(env: env, track: track, gameVisibility: { StaticGameVisibility.visible }).showsGame)
        #expect(!InboxExtras(env: env, track: track, gameVisibility: { StaticGameVisibility.hidden }).showsGame)
        #expect(!InboxExtras(env: env, track: track, gameVisibility: { StaticGameVisibility.unreadable }).showsGame)
        let extras = InboxExtras(env: env, track: track, gameVisibility: { StaticGameVisibility.hidden })
        #expect(extras.dropContent(for: dropNote(data: dropData))?.xpText == nil)
        let visible = InboxExtras(env: env, track: track, gameVisibility: { StaticGameVisibility.visible })
        #expect(visible.dropContent(for: dropNote(data: dropData))?.xpText == "+25 XP")
    }

    @Test func test_estimateDropIsNotACard() {
        let estimate = dropNote(data: ["drop": ["from": 500, "to": 454, "amount": 46, "observed": false]])
        let (_, env, _) = header()
        let extras = InboxExtras(env: env, track: { _ in })
        #expect(extras.dropContent(for: estimate) == nil)
    }

    @Test func test_dropSeenOncePerNotification() {
        let events = Events()
        let (_, env, _) = header()
        let extras = InboxExtras(env: env, track: { events.record($0) })
        let note = dropNote(id: 7, data: dropData)
        extras.dropSeen(note)
        extras.dropSeen(note)
        extras.dropSeen(dropNote(id: 8, data: dropData))
        extras.dropSeen(dropNote(id: 9, data: .null))
        #expect(events.drops == ["hotel:false:in_app", "flight:false:in_app"])
    }

    // MARK: Digest

    @Test func test_digestRowTolerance() {
        LanguageController.withLanguage(.en) {
            let full: JSONValue = [
                "digest": [
                    "week": "2026-W46",
                    "watches": [
                        ["kind": "hotel", "watch_id": 4, "title": "Lumen Hotel", "latest": 352, "change_7d": -12.5, "lowest": 340,
                         "checked_at": "2026-11-14T10:00:00Z", "currency": "EUR"],
                        ["kind": "spaceship", "title": "Mystery", "latest": "99.5", "change_7d": 8, "future_key": [1, 2]],
                        ["watch_id": "5"],
                        "not an object",
                    ],
                    "savings": ["total_usd": 245, "drops_caught": 4],
                ]
            ]
            let note = AppNotification(id: 1, kind: "price_digest", title: "Your weekly digest", data: full)
            #expect(note.isPriceDigest)
            guard let digest = note.digest else {
                Issue.record("no digest")
                return
            }
            let lines = DigestContent.lines(digest)
            #expect(lines.count == 3)
            #expect(lines[0].title == "Lumen Hotel" && lines[0].latest == "€352.00" && lines[0].change == "−€12.50")
            #expect(lines[0].lowest == "Lowest: €340.00")
            // No currency known: a plain number, never a guessed symbol. Unknown kinds and missing titles still give a line.
            #expect(lines[1].title == "Mystery" && lines[1].latest == "99.50" && lines[1].change == "+8.00")
            #expect(lines[2].title.isEmpty && lines[2].latest == nil && lines[2].change == nil)
            #expect(DigestContent.savingsLine(digest) == "Drops caught: $245.00")
            // Absent or malformed data.
            let bare = AppNotification(id: 2, kind: "price_digest", data: .null)
            #expect(bare.digest == nil)
            let empty = AppNotification(id: 3, kind: "price_digest", data: ["digest": ["watches": []]])
            #expect(empty.digest.map(DigestContent.lines) == [])
            #expect(AppNotification(id: 4, kind: "price_digest", data: ["digest": "oops"]).digest == nil)
        }
    }

    @Test func test_unknownAndGroupedRowsNeedNoExtras() {
        let (_, env, _) = header()
        let extras = InboxExtras(env: env, track: { _ in })
        let future = AppNotification(id: 1, kind: "brand_new_kind", title: "Hello", data: ["x": 1])
        #expect(extras.dropContent(for: future) == nil && future.digest == nil && !future.isPriceDigest)
        // A grouped push: the server's title says "3 prices dropped"; no drop, no card, nothing to break.
        let grouped = AppNotification(id: 2, kind: "fare_drop", title: "3 prices dropped", data: ["group_count": "3"])
        #expect(grouped.groupCount == 3)
        #expect(extras.dropContent(for: grouped) == nil)
        // A pending watch's note carries nothing at all.
        #expect(extras.dropContent(for: AppNotification(id: 3, kind: "fare_drop", data: .null)) == nil)
    }

    @Test func test_digestTapOpensAlertsAndTracksOnce() async {
        let events = Events()
        let digest = AppNotification(id: 5, kind: "price_digest", title: "Your weekly digest", data: ["digest": ["watches": []]])
        let fakes = FakeRepositories()
        fakes.notifications.onMarkRead.returns(0)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        let model = NotificationsModel(env: env, track: { events.record($0) }, now: { fixedNow })
        model.show(items: [digest], unread: 1)
        await model.open(digest)
        #expect(env.recordedRoutes == [.alerts(kind: nil, watchID: nil)])
        #expect(events.digests == ["in_app"])
        #expect(fakes.notifications.onMarkRead.lastCall?.ids == [5])
    }
}
