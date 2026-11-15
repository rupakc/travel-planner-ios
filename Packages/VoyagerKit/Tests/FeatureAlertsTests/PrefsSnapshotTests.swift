import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureAlerts

@MainActor
final class PrefsSnapshotTests: XCTestCase {
    private func canvas(
        _ name: String, _ device: SnapshotDevice = .iPhoneSE, dark: Bool = false, language: AppLanguage = .en, height: CGFloat = 1500,
        ax5: Bool = false
    ) -> SnapshotConfig {
        let isPad = device == .iPadPro11
        return SnapshotConfig(
            name: name, device: device.config, dark: dark, language: language,
            size: ax5 ? .accessibilityExtraExtraExtraLarge : .large,
            canvas: CGSize(width: isPad ? 834 : 320, height: isPad ? 1100 : height))
    }

    private let v2 = ClientConfig(features: ["alerts_api": .number(2), "price_alerts_v2": .bool(true), "live_prices": .bool(true)])

    private let prefs = AlertPrefs(
        digestWeekly: true, digestPush: false, digestDay: 7, instant: .targetsOnly,
        quietHours: QuietHoursPref(enabled: true, start: "22:00", end: "07:00"),
        dailyCap: DailyCaps(flight: 3, hotel: 2, activity: 5, trip: 1), groupWindowMin: 15, timezone: "Europe/Berlin",
        quietHoursActive: false)

    private func screen(_ prefs: AlertPrefs) async -> AlertPrefsView {
        let fakes = FakeRepositories()
        fakes.alertsV2.onPrefs.returns(prefs)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: v2)
        let model = AlertPrefsModel(env: env, track: { _ in })
        await model.load()
        return AlertPrefsView(model: model)
    }

    func test_prefsLight() async {
        let view = await screen(prefs)
        await assertSnapshots(
            of: { view }, named: "AlertPrefsLight", configs: [canvas("se-light"), canvas("se-dark", dark: true)], layout: .screen)
    }

    func test_prefsDigestOffNoTimezone() async {
        var off = AlertPrefs(timezone: nil)
        off.quietHours.enabled = true
        let view = await screen(off)
        await assertSnapshots(of: { view }, named: "AlertPrefsDigestOff", configs: [canvas("se-light")], layout: .screen)
    }

    func test_prefsDarkAX5() async {
        let view = await screen(prefs)
        await assertSnapshots(
            of: { view }, named: "AlertPrefsDarkAX5",
            configs: [canvas("se-de-dark-ax5", dark: true, language: .de, height: 6500, ax5: true)], layout: .screen)
    }

    func test_prefsLongLanguages() async {
        let view = await screen(prefs)
        await assertSnapshots(
            of: { view }, named: "AlertPrefsHI",
            configs: [canvas("hi", language: .hi, height: 1600)], layout: .screen)
    }

    func test_prefsIPad() async {
        let view = await screen(prefs)
        await assertSnapshots(of: { view }, named: "AlertPrefsIPad", configs: [canvas("ipad-light", .iPadPro11)], layout: .screen)
    }

    // MARK: Suggestions

    private func suggestionRows() -> [SuggestionsModel.Row] {
        func make(_ kind: WatchKind, _ title: String, _ subtitle: String, _ reason: SuggestionReason) -> WatchSuggestion {
            WatchSuggestion(kind: kind, title: title, subtitle: subtitle, spec: .object([:]), reason: reason)
        }
        return [
            SuggestionsModel.Row(make(.flight, "Berlin → Lisbon", "1 Dec – 8 Dec", .selectedInPlan), id: 0),
            SuggestionsModel.Row(make(.hotel, "Lumen Hotel", "Lisbon · 1–8 Dec", .selectedInPlan), id: 1, selected: false),
            SuggestionsModel.Row(make(.activity, "Belém walking tour", "Lisbon", .departureSoon), id: 2, status: .already),
            SuggestionsModel.Row(make(.trip, "Your Lisbon trip", "1 Dec – 8 Dec", .tripTotal), id: 3),
        ]
    }

    private func sheet(rows: [SuggestionsModel.Row]) -> SuggestionsSheet {
        let env = AppEnvironment.fake(clientConfig: v2)
        let model = SuggestionsModel(env: env, planID: 3, track: { _ in })
        model.show(rows)
        return SuggestionsSheet(model: model, loadsOnAppear: false)
    }

    func test_suggestionsSheet() async {
        let view = sheet(rows: suggestionRows())
        await assertSnapshots(
            of: { view }, named: "SuggestionsSheet",
            configs: [canvas("se-light", height: 760), canvas("se-dark", dark: true, height: 760)], layout: .screen)
    }

    func test_suggestionsSheetProgress() async {
        var rows = suggestionRows()
        rows[0].status = .done
        rows[3].status = .failed("That's your limit of active watches. Remove one on the Alerts page.")
        let view = sheet(rows: rows)
        await assertSnapshots(
            of: { view }, named: "SuggestionsSheetProgress", configs: [canvas("se-light", height: 820)], layout: .screen)
    }

    func test_suggestionsSheetGermanAX5() async {
        let view = sheet(rows: suggestionRows())
        await assertSnapshots(
            of: { view }, named: "SuggestionsSheetAX5",
            configs: [canvas("se-de-ax5", language: .de, height: 4200, ax5: true)], layout: .screen)
    }
}
