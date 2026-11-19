import Foundation
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerData
import VoyagerEnv
import VoyagerModel

@testable import FeatureSettings

@MainActor
@Suite struct NotificationSettingsModelTests {
    private func config(api: Int = 1, game: Bool = true) -> ClientConfig {
        ClientConfig(features: ["notifications_api": .number(Double(api)), "game": .bool(game)])
    }

    /// The notification events as short strings (`TelemetryEvent.wire` is internal to Telemetry).
    private final class Events: @unchecked Sendable {
        var all: [String] = []

        func record(_ event: TelemetryEvent) {
            switch event {
            case .notifSettingsView: all.append("view")
            case .notifCategoryToggle(let category, let on): all.append("toggle:\(category):\(on)")
            case .notifQuietHoursChange(let enabled): all.append("quiet:\(enabled)")
            case .notifCapChange(let cap): all.append("cap:\(cap)")
            default: all.append("other")
            }
        }
    }

    /// A server that keeps what it was sent and answers the full object, like the real route.
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var state: NotificationSettings

        init(_ state: NotificationSettings = NotificationSettings(timezone: "Asia/Kolkata")) { self.state = state }

        func apply(_ patch: NotificationSettingsPatch) -> NotificationSettings {
            lock.lock()
            defer { lock.unlock() }
            for (category, enabled) in patch.categories ?? [:] { state.categories[category] = enabled }
            if let quiet = patch.quietHours { state.quietHours = quiet }
            if let cap = patch.dailyCap { state.dailyCap = cap }
            return state
        }

        func install(in fakes: FakeRepositories) {
            fakes.notificationSettings.onGet.handler = { [self] _ in apply(NotificationSettingsPatch()) }
            fakes.notificationSettings.onUpdate.handler = { [self] patch in apply(patch) }
        }
    }

    private func make(
        _ fakes: FakeRepositories, permission: NotificationPermissionState = .allowed, api: Int = 1,
        game: StaticGameVisibility = .visible, events: Events = Events()
    ) -> NotificationSettingsModel {
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config(api: api))
        return NotificationSettingsModel(
            env: env, permission: FakeNotificationPermission(permission), gameVisibility: { game },
            track: { events.record($0) })
    }

    @Test func test_hiddenWithoutNotificationsApi() async {
        let fakes = FakeRepositories()
        let model = make(fakes, api: 0)
        await model.load()
        #expect(model.phase == .unavailable)
        #expect(fakes.notificationSettings.onGet.callCount == 0)
    }

    @Test func test_loadsAndTracksTheViewOnce() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(NotificationSettings(categories: [.weather: false], dailyCap: 5))
        let events = Events()
        let model = make(fakes, events: events)
        await model.load()
        await model.load()
        #expect(model.phase == .loaded && !model.isOn(.weather) && model.isOn(.social) && model.settings.dailyCap == 5)
        #expect(events.all == ["view"])
    }

    @Test func test_loadFailureOffersRetryAndRecovers() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.fails(APIError.network)
        let model = make(fakes)
        await model.load()
        #expect(model.phase == .failed && model.loadError != nil)
        fakes.notificationSettings.onGet.returns(NotificationSettings())
        await model.load()
        #expect(model.phase == .loaded && model.loadError == nil)
    }

    @Test func test_settingsRoundTrip() async {
        let fakes = FakeRepositories()
        Server().install(in: fakes)
        let events = Events()
        let model = make(fakes, events: events)
        await model.load()
        model.setCategory(.nearby, on: false)
        await model.waitForSaves()
        model.setCap(7)
        await model.waitForSaves()
        model.setQuietEnabled(false)
        await model.waitForSaves()
        model.setQuietTimes(start: "23:00", end: "06:30")
        await model.waitForSaves()
        #expect(fakes.notificationSettings.onUpdate.calls.count == 4)
        #expect(fakes.notificationSettings.onUpdate.calls[0] == NotificationSettingsPatch(categories: [.nearby: false]))
        #expect(fakes.notificationSettings.onUpdate.calls[1] == NotificationSettingsPatch(dailyCap: 7))
        #expect(!model.isOn(.nearby) && model.settings.dailyCap == 7 && !model.saveFailed)
        #expect(model.settings.quietHours == QuietHoursPref(enabled: false, start: "23:00", end: "06:30"))
        #expect(events.all == ["view", "toggle:nearby:false", "cap:7", "quiet:false", "quiet:false"])
    }

    @Test func test_invalidIsUndoneWithAMessage() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(NotificationSettings(dailyCap: 3))
        let code = NotificationSettingsFailure.invalid.rawValue
        fakes.notificationSettings.onUpdate.fails(
            APIError.client(status: 422, detail: "bad", code: code, body: .object(["error_code": .string(code)])))
        let model = make(fakes)
        await model.load()
        model.setCap(9)
        #expect(model.settings.dailyCap == 9)  // optimistic until the answer
        await model.waitForSaves()
        #expect(model.settings.dailyCap == 3 && model.saveFailed && model.phase == .loaded)
        model.setCategory(.social, on: false)
        #expect(!model.saveFailed)
    }

    @Test func test_capIsClampedToOneToTen() async {
        let fakes = FakeRepositories()
        Server().install(in: fakes)
        let model = make(fakes)
        await model.load()
        model.setCap(99)
        await model.waitForSaves()
        #expect(fakes.notificationSettings.onUpdate.lastCall == NotificationSettingsPatch(dailyCap: 10))
        model.setCap(-4)
        await model.waitForSaves()
        #expect(fakes.notificationSettings.onUpdate.lastCall == NotificationSettingsPatch(dailyCap: 1))
    }

    @Test func test_quietHoursSharedWithAlertPrefs() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(
            NotificationSettings(quietHours: QuietHoursPref(enabled: true, start: "22:00", end: "07:00")))
        let model = make(fakes)
        await model.load()
        #expect(model.settings.quietHours.start == "22:00")
        // The alert prefs screen saved other times on the same server value; the next appearance refetches them.
        fakes.notificationSettings.onGet.returns(
            NotificationSettings(quietHours: QuietHoursPref(enabled: true, start: "23:30", end: "06:00")))
        await model.load()
        #expect(model.settings.quietHours == QuietHoursPref(enabled: true, start: "23:30", end: "06:00"))
        #expect(fakes.notificationSettings.onGet.callCount == 2)
    }

    @Test func test_editsMadeDuringASaveAreMergedAndKept() async {
        let fakes = FakeRepositories()
        Server().install(in: fakes)
        let model = make(fakes)
        await model.load()
        model.setCategory(.weather, on: false)
        model.setCategory(.social, on: false)  // while the first save is in flight
        model.setCap(5)
        await model.waitForSaves()
        #expect(!model.isOn(.weather) && !model.isOn(.social) && model.settings.dailyCap == 5)
        #expect(fakes.notificationSettings.onUpdate.callCount == 2)
        #expect(fakes.notificationSettings.onUpdate.lastCall == NotificationSettingsPatch(categories: [.social: false], dailyCap: 5))
    }

    @Test func test_quizSwitchHiddenWhenGameIsHidden() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(NotificationSettings())
        for hidden in [StaticGameVisibility.hidden, .unreadable, StaticGameVisibility(gameFeature: false, hideGameSetting: false)] {
            let model = make(fakes, game: hidden)
            await model.load()
            #expect(!model.categories.contains(.quiz) && model.categories.count == 6)
        }
        let shown = make(fakes, game: .visible)
        await shown.load()
        #expect(shown.categories == NotificationCategory.allCases)
    }

    @Test func test_defaultVisibilityShowsTheQuizSwitchWhenTheGameIsOn() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(NotificationSettings())
        func model(game: Bool) -> NotificationSettingsModel {
            let features: [String: JSONValue] = ["notifications_api": .number(1), "game": .bool(game)]
            let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: features))
            return NotificationSettingsModel(env: env, permission: FakeNotificationPermission(.allowed), track: { _ in })
        }
        let on = model(game: true)
        await on.load()
        #expect(on.categories == NotificationCategory.allCases)
        let off = model(game: false)
        await off.load()
        #expect(!off.categories.contains(.quiz))
    }

    @Test func test_pushStatusNotes() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(NotificationSettings(pushAPNS: false))
        let none = make(fakes)
        await none.load()
        #expect(none.pushUnavailable && !none.showsNoDevices)
        fakes.notificationSettings.onGet.returns(NotificationSettings(pushAPNS: true, devices: 0))
        let live = make(fakes)
        await live.load()
        #expect(!live.pushUnavailable && live.showsNoDevices)
        fakes.notificationSettings.onGet.returns(NotificationSettings(pushAPNS: true, devices: 2))
        let registered = make(fakes)
        await registered.load()
        #expect(!registered.pushUnavailable && !registered.showsNoDevices)
    }

    @Test func test_permissionStateAndRequest() async {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(NotificationSettings())
        let asked = FakeNotificationPermission(.notDetermined)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        let model = NotificationSettingsModel(env: env, permission: asked, track: { _ in })
        await model.load()
        #expect(model.permission == .notDetermined)
        await model.requestPermission()
        #expect(model.permission == .allowed && asked.requestCount == 1)
        let denied = make(fakes, permission: .denied)
        await denied.load()
        #expect(denied.permission == .denied)
    }

    @Test func test_clockTextRoundTrips() {
        #expect(QuietClock.text(QuietClock.date("07:05")) == "07:05")
        #expect(QuietClock.text(QuietClock.date("23:59")) == "23:59")
        #expect(QuietClock.text(QuietClock.date("00:00")) == "00:00")
    }
}
