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
struct AlertPrefsTests {
    private let v2 = ClientConfig(features: ["alerts_api": .number(2), "price_alerts_v2": .bool(true), "live_prices": .bool(true)])

    private func make(
        _ prefs: AlertPrefs = AlertPrefs(timezone: "Europe/Berlin"), config: ClientConfig? = nil
    ) -> (AlertPrefsModel, FakeRepositories, TrackLog) {
        let fakes = FakeRepositories()
        fakes.alertsV2.onPrefs.returns(prefs)
        // The server applies a patch to what it holds and answers the whole object.
        fakes.alertsV2.onUpdatePrefs.handler = { patch in
            var next = prefs
            next.apply(patch)
            return next
        }
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config ?? v2)
        let log = TrackLog()
        return (AlertPrefsModel(env: env, track: { log.events.append($0) }), fakes, log)
    }

    @MainActor final class TrackLog {
        var events: [TelemetryEvent] = []
        var fields: [String] {
            events.compactMap { if case .alertPrefsChange(let field) = $0 { field } else { nil } }
        }
    }

    @Test func test_loadsThePrefs() async {
        let (model, _, _) = make(AlertPrefs(digestWeekly: true, digestDay: 5, timezone: "Asia/Kolkata"))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.prefs.digestWeekly && model.prefs.digestDay == 5 && model.prefs.timezone == "Asia/Kolkata")
    }

    @Test func test_olderBackendShowsNothingAndCallsNothing() async {
        let (model, fakes, _) = make(config: ClientConfig(features: [:]))
        await model.load()
        #expect(model.phase == .unavailable)
        #expect(fakes.alertsV2.onPrefs.callCount == 0)
    }

    @Test func test_digestPushDisabledWithoutWeekly() async {
        let (model, fakes, _) = make()
        await model.load()
        #expect(!model.canEditDigestPush)
        model.setDigestPush(true)
        await model.waitForSaves()
        #expect(!model.prefs.digestPush && fakes.alertsV2.onUpdatePrefs.callCount == 0)
        model.setDigestWeekly(true)
        await model.waitForSaves()
        #expect(model.canEditDigestPush)
        model.setDigestPush(true)
        await model.waitForSaves()
        #expect(model.prefs.digestPush)
        #expect(fakes.alertsV2.onUpdatePrefs.calls.map(\.digestPush) == [nil, true])
    }

    @Test func test_prefsInvalidKeepsPreviousSetting() async {
        let (model, fakes, _) = make()
        await model.load()
        fakes.alertsV2.onUpdatePrefs.fails(
            APIError.client(status: 422, detail: "bad", code: "alert_prefs_invalid", body: .object(["error_code": "alert_prefs_invalid"])))
        model.setCap(.hotel, 9)
        #expect(model.prefs.dailyCap.hotel == 9)  // shown at once
        await model.waitForSaves()
        #expect(model.prefs.dailyCap.hotel == DailyCaps().hotel)
        #expect(model.saveFailure == .invalid)
        #expect(model.saveFailureMessage == L10n.text(K.alertPrefs.error.invalid))
        // The next edit clears the message.
        fakes.alertsV2.onUpdatePrefs.handler = { _ in AlertPrefs(timezone: "Europe/Berlin") }
        model.setGroupWindow(30)
        #expect(model.saveFailure == nil)
        await model.waitForSaves()
    }

    @Test func test_otherFailureShowsTheSaveMessage() async {
        let (model, fakes, _) = make()
        await model.load()
        fakes.alertsV2.onUpdatePrefs.fails(APIError.network)
        model.setInstantTargetsOnly(true)
        await model.waitForSaves()
        #expect(model.prefs.instant == .all)
        #expect(model.saveFailure == .failed)
        #expect(model.saveFailureMessage == L10n.text(K.alertPrefs.error.save))
    }

    @Test func test_timezoneReadOnly() async throws {
        let (model, fakes, _) = make(AlertPrefs(quietHours: QuietHoursPref(enabled: true), timezone: nil))
        await model.load()
        #expect(model.quietHoursNeedTimezone)
        model.setQuietTimes(start: "21:30")
        await model.waitForSaves()
        let sent = try #require(fakes.alertsV2.onUpdatePrefs.lastCall)
        let keys = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(sent)) as? [String: Any]).keys
        #expect(!keys.contains("timezone") && !keys.contains("quiet_hours_active"))
        #expect(Set(keys) == ["quiet_hours"])
        // Even the full writable set never carries the server's two keys.
        let all = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model.prefs.writable)) as? [String: Any]
        #expect(all?["timezone"] == nil && all?["quiet_hours_active"] == nil)
    }

    @Test func test_savesOnlyTheChangedKey() async throws {
        let (model, fakes, log) = make()
        await model.load()
        model.setCap(.trip, 7)
        await model.waitForSaves()
        let sent = try #require(fakes.alertsV2.onUpdatePrefs.lastCall)
        #expect(sent.dailyCap?.trip == 7 && sent.digestWeekly == nil && sent.quietHours == nil && sent.groupWindowMin == nil)
        #expect(log.fields == ["cap"])
    }

    @Test func test_limitsAreClamped() async {
        let (model, _, _) = make()
        await model.load()
        model.setCap(.flight, 99)
        model.setGroupWindow(500)
        model.setDigestDay(9)
        await model.waitForSaves()
        #expect(model.prefs.dailyCap.flight == 10 && model.prefs.groupWindowMin == 120 && model.prefs.digestDay == 1)
    }

    @Test func test_everyChangeReportsItsField() async {
        let (model, _, log) = make()
        await model.load()
        model.setDigestWeekly(true)
        model.setDigestDay(3)
        model.setInstantTargetsOnly(true)
        model.setQuietEnabled(true)
        model.setGroupWindow(45)
        model.setCap(.activity, 2)
        await model.waitForSaves()
        #expect(log.fields == ["digest", "digest", "instant", "quiet_hours", "group", "cap"])
    }

    @Test func test_editsMadeWhileSavingAreMergedAndSent() async {
        let (model, fakes, _) = make()
        await model.load()
        model.setDigestWeekly(true)  // starts the first save
        model.setDigestDay(4)  // queued behind it
        model.setGroupWindow(60)  // merged with the queued one
        await model.waitForSaves()
        #expect(fakes.alertsV2.onUpdatePrefs.callCount == 2)
        #expect(fakes.alertsV2.onUpdatePrefs.lastCall?.digestDay == 4 && fakes.alertsV2.onUpdatePrefs.lastCall?.groupWindowMin == 60)
        #expect(model.prefs.digestWeekly && model.prefs.digestDay == 4 && model.prefs.groupWindowMin == 60)
    }
}
