import AuthCore
import DesignSystem
import Domain
import Foundation
import Networking
import Observation
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureSettings
@testable import Telemetry

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
    var consent: [Bool] = []
}

private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var fired: Bool { lock.withLock { value } }
    func fire() { lock.withLock { value = true } }
}

@MainActor
private func make(user: User? = .sample, fakes: FakeRepositories = FakeRepositories(), choice: ConsentChoice? = nil)
    -> (SettingsModel, AppEnvironment, Recorder)
{
    let env = AppEnvironment.fake(user: user, fakes: fakes)
    let rec = Recorder()
    let model = SettingsModel(
        env: env, consentChoice: { choice }, timeZone: "America/New_York",
        track: { rec.events.append($0) }, setConsent: { rec.consent.append($0) })
    return (model, env, rec)
}

@MainActor
struct SettingsModelTests {
    @Test func test_themePersistsAndEmits() {
        let (model, env, rec) = make()
        #expect(model.theme == .light)
        model.setTheme(.dark)
        #expect(env.theme.preference == .dark)
        #expect(env.theme.colorScheme == .dark)
        model.setTheme(.dark)  // no change, no second event
        model.setTheme(.system)
        #expect(env.theme.colorScheme == nil)
        let names = rec.events.compactMap { event -> String? in
            if case .themeChange(let value) = event { return value }
            return nil
        }
        #expect(names == ["dark", "system"])
    }

    @Test func test_languageSwitchReRenders() async {
        let (model, env, rec) = make()
        let flag = ChangeFlag()
        withObservationTracking { _ = env.language.language } onChange: { flag.fire() }
        model.setLanguage(.hi)
        #expect(flag.fired)
        #expect(env.language.language == .hi)
        #expect(env.language.locale.identifier == "hi-IN")
        #expect(model.language == .hi)
        guard case .languageChange(.hi)? = rec.events.last else {
            Issue.record("no languageChange event")
            return
        }
    }

    @Test func test_privacyOffClearsQueue() {
        let (model, _, rec) = make(choice: .granted)
        #expect(model.telemetryOn)
        model.setTelemetry(false)
        #expect(!model.telemetryOn)
        #expect(rec.consent == [false])  // Telemetry.setConsent(false) empties the queue and the store
        model.setTelemetry(false)
        #expect(rec.consent == [false])
        model.setTelemetry(true)
        #expect(rec.consent == [false, true])
    }

    @Test func test_privacyDefaultsFollowRegion() {
        let env = AppEnvironment.fake()
        #expect(SettingsModel(env: env, consentChoice: { nil }, timeZone: "America/New_York").telemetryOn)
        #expect(!SettingsModel(env: env, consentChoice: { nil }, timeZone: "Europe/Berlin").telemetryOn)
        #expect(!SettingsModel(env: env, consentChoice: { .denied }, timeZone: "America/New_York").telemetryOn)
    }

    @Test func test_privacyChoicesRequestsTheConsentCard() {
        let (model, env, _) = make()
        model.reopenConsent()
        #expect(env.consentPromptRequested)
    }

    @Test func test_adminRowOnlyForAdmins() {
        #expect(make(user: .sampleAdmin).0.showsAdminRow)
        #expect(!make(user: .sample).0.showsAdminRow)
        #expect(make(user: .sampleAdmin).0.isAdmin)
        #expect(make(user: .sample).0.username == "amy")
    }

    @Test func test_rowsOpenTheirRoutes() {
        let (model, env, _) = make()
        model.open(.preferences)
        model.open(.tasteProfile)
        model.open(.onboarding(fromSettings: true))
        #expect(env.recordedRoutes == [.preferences, .tasteProfile, .onboarding(fromSettings: true)])
    }

    @Test func test_featureSwitchesFollowTheCatalogue() {
        let (model, env, _) = make()
        env.device.travellerTypes = []
        #expect(!model.isFeatureOn("compare"))
        model.setFeature("compare", on: true)
        #expect(model.isFeatureOn("compare"))
        #expect(env.device.featureEnabled == ["compare"])
        model.setFeature("compare", on: false)
        #expect(!model.isFeatureOn("compare"))
        #expect(env.device.featureEnabled.isEmpty)
        env.device.travellerTypes = ["BUDGET_BACKPACKER"]
        #expect(model.isFeatureOn("compare"))  // a default for this traveller
        model.setFeature("compare", on: false)
        #expect(!model.isFeatureOn("compare"))
        #expect(env.device.featureDisabled == ["compare"])
        model.setFeature("compare", on: true)
        #expect(model.isFeatureOn("compare"))
        #expect(env.device.featureDisabled.isEmpty)
    }

    @Test func test_signOutUnregistersTheTokenFirst() async {
        let fakes = FakeRepositories()
        let (model, env, _) = make(fakes: fakes)
        env.device.pushToken = "tok-123"
        await model.signOut()
        #expect(fakes.devices.onUnregister.calls == ["tok-123"])
        #expect(env.device.pushToken == nil)
        #expect(env.auth.session == nil)
    }

    @Test func test_signOutWithoutTokenSkipsTheCall() async {
        let fakes = FakeRepositories()
        let (model, env, _) = make(fakes: fakes)
        await model.signOut()
        #expect(fakes.devices.onUnregister.calls.isEmpty)
        #expect(env.auth.session == nil)
    }

    @Test func test_signOutStillHappensWhenUnregisterFails() async {
        let fakes = FakeRepositories()
        fakes.devices.onUnregister.handler = { _ in throw APIError.server(status: 500, detail: nil) }
        let (model, env, _) = make(fakes: fakes)
        env.device.pushToken = "tok"
        await model.signOut()
        #expect(env.auth.session == nil)
        #expect(env.device.pushToken == "tok")  // kept, so the unregister can be retried
    }

    @Test func test_privacyFollowsTheConsentCardAnswer() {
        var choice: ConsentChoice?
        let model = SettingsModel(env: AppEnvironment.fake(), consentChoice: { choice }, timeZone: "Europe/Berlin")
        #expect(!model.telemetryOn)  // EU zone, not answered yet
        choice = .granted  // answered on the consent card
        model.refreshConsent()
        #expect(model.telemetryOn)
        choice = .denied
        model.refreshConsent()
        #expect(!model.telemetryOn)
    }

    @Test func test_privacyOffEmptiesTheRealTelemetryBuffer() async {
        let suite = UserDefaults(suiteName: "settings-telemetry-\(UUID().uuidString)")!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tel-\(UUID().uuidString)")
        let telemetry = Telemetry()
        telemetry.configure(
            TelemetryBootstrap(
                appVersion: "1.0.0", locale: { "en" }, endpoint: { nil }, token: { nil },
                remote: TelemetryRemoteConfig(enabled: true), storeDirectory: directory,
                timeZone: { TimeZone(identifier: "America/New_York") ?? .gmt }),
            defaults: suite, background: false)
        telemetry.track(.themeChange("dark"))
        telemetry.track(.themeChange("light"))
        guard let core = telemetry.core else {
            Issue.record("telemetry not configured")
            return
        }
        #expect(!core.queuedEvents().isEmpty)
        let model = SettingsModel(
            env: AppEnvironment.fake(), consentChoice: { .granted }, timeZone: "America/New_York",
            telemetry: telemetry)
        model.setTelemetry(false)
        await core.settle()
        #expect(core.queuedEvents().isEmpty)
        #expect(Consent.stored(suite) == .denied)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(!leftovers.contains("tq.json"))
    }

    @Test func test_signOutLeavesNothingForTheNextUser() async {
        let (model, env, _) = make()
        let started = env.startDeferredWork()
        await started.value
        env.plan.searchData = ["destination": "Kyoto"]
        env.plan.toggle(field: "activities", item: ["name": "Fushimi Inari"])
        let thread = env.chatThreads.create()
        env.chatThreads.append(["role": "user", "content": "Tokyo in April?"], to: thread.id)
        await env.flushPersistence()
        #expect(env.chatThreads.username == "amy")

        await model.signOut()
        // The shell follows the session: the plan and chats are the signed-out guest's, empty.
        for _ in 0..<200 where env.chatThreads.username != nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(env.auth.session == nil)
        #expect(env.chatThreads.username == nil)
        #expect(env.chatThreads.threads.isEmpty)
        #expect(env.plan.searchData == nil)
        #expect(env.plan.selections == Selections.empty)
        #expect(env.plan.savedPlanID == nil)
    }

    @Test func test_alertPollAndPushTokenPersist() {
        let defaults = UserDefaults(suiteName: "settings-\(UUID().uuidString)")!
        let first = DeviceSettings(defaults: defaults)
        #expect(first.alertPoll)
        first.alertPoll = false
        first.pushToken = "abc"
        let second = DeviceSettings(defaults: defaults)
        #expect(!second.alertPoll)
        #expect(second.pushToken == "abc")
    }
}

@MainActor
struct FeedbackModelTests {
    @Test func test_feedbackMax500() async {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes)
        let model = FeedbackModel(env: env)
        model.updateMessage(String(repeating: "x", count: 600))
        #expect(model.message.count == 500)
        #expect(!model.canSend)  // no rating yet
        model.rating = 4
        model.category = "bug"
        await model.send()
        let sent = fakes.feedback.onSubmit.calls
        #expect(sent.count == 1)
        #expect(sent[0].message?.count == 500)
        #expect(sent[0].rating == 4)
        #expect(sent[0].category == "bug")
        #expect(model.sent)
    }

    @Test func test_ratingRange() {
        let model = FeedbackModel(env: AppEnvironment.fake())
        for bad in [0, 6, -1] {
            model.rating = bad
            #expect(!model.canSend)
        }
        model.rating = 5
        #expect(model.canSend)
    }

    @Test func test_emptyMessageIsOmittedAndFailureShowsError() async {
        let fakes = FakeRepositories()
        fakes.feedback.onSubmit.handler = { _ in throw APIError.server(status: 503, detail: nil) }
        let model = FeedbackModel(env: AppEnvironment.fake(fakes: fakes))
        model.rating = 3
        model.updateMessage("   ")
        await model.send()
        #expect(fakes.feedback.onSubmit.calls[0].message == nil)
        #expect(!model.sent)
        #expect(model.error != nil)
    }
}
