import Domain
import Foundation
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureOnboarding

private struct Boom: Error {}

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
    var outcomes: [OnboardingOutcome] = []

    /// (step, action) of every onboarding event.
    var steps: [String] {
        events.compactMap { event in
            if case .onboardingStep(let step, let action) = event { return "\(step):\(action.rawValue)" }
            return nil
        }
    }
}

@MainActor
private func makeModel(
    fakes: FakeRepositories = FakeRepositories(),
    fromSettings: Bool = false,
    prepare: (AppEnvironment) -> Void = { _ in }
) -> (OnboardingModel, AppEnvironment, Recorder) {
    let env = AppEnvironment.fake(fakes: fakes)
    env.device.onboardingCompleted = false
    prepare(env)
    let recorder = Recorder()
    let model = OnboardingModel(
        env: env, fromSettings: fromSettings,
        track: { recorder.events.append($0) },
        requestNotifications: { true },
        onFinish: { recorder.outcomes.append($0) })
    return (model, env, recorder)
}

@MainActor
struct OnboardingModelTests {
    @Test func test_resumesAtSavedStep() {
        let (model, _, _) = makeModel { $0.device.onboardingStep = 2 }
        #expect(model.step == .homeAndPassport)
    }

    @Test func test_resumeKeepsSavedAnswersAndPersistsProgress() {
        let (model, env, _) = makeModel { $0.device.quizAnswers = ["pace": ["packed"]] }
        #expect(model.answers["pace"] == ["packed"])
        model.next()
        #expect(env.device.onboardingStep == OnboardingStep.howYouTravel.rawValue)
    }

    @Test func test_skipRecordsTelemetry() {
        let (model, _, recorder) = makeModel()
        model.start()
        model.skip()
        #expect(recorder.steps == ["1:view", "1:skip", "2:view"])
        #expect(model.step == .howYouTravel)
    }

    @Test func test_finishMergesPreferences() async throws {
        let fakes = FakeRepositories()
        fakes.preferences.onGet.returns(Preferences(nationality: "Indian", interests: ["art"]))
        let (model, env, recorder) = makeModel(fakes: fakes)
        let history = try #require(TravellerQuiz.question(TravellerQuiz.interests))
        model.toggle(try #require(history.options.first { $0.id == "history_culture" }), in: history)
        await model.finish().value
        let sent = try #require(fakes.preferences.onPut.lastCall)
        #expect(sent.nationality == "Indian")
        #expect(sent.interests == ["art", "history", "culture"])
        #expect(env.device.onboardingCompleted)
        #expect(env.device.travellerTypes.first == TravellerType.cultureFoodie.rawValue)
        #expect(env.device.quizAnswers[TravellerQuiz.interests] == ["history_culture"])
        #expect(recorder.outcomes == [.completed])
    }

    @Test func test_finishAndPlanOpensSearch() async {
        let fakes = FakeRepositories()
        fakes.preferences.onGet.returns(Preferences())
        let (model, env, _) = makeModel(fakes: fakes)
        await model.finishAndPlan().value
        #expect(env.recordedRoutes == [.explore(.search)])
    }

    @Test func test_pickedPassportAndHomeAreSent() async throws {
        let fakes = FakeRepositories()
        fakes.preferences.onGet.returns(Preferences(nationality: "Indian"))
        let (model, _, _) = makeModel(fakes: fakes)
        model.choose(nationality: NationalitySuggestion(nationality: "German", countryCode: "DE"))
        model.choose(airport: AirportSuggestion(iataCode: "FRA", city: "Frankfurt", country: "Germany"))
        await model.finish().value
        let sent = try #require(fakes.preferences.onPut.lastCall)
        #expect(sent.nationality == "German")
        #expect(sent.currentResidence == "Germany")
    }

    @Test func test_preferencesFailureOffersContinue() async {
        let fakes = FakeRepositories()
        fakes.preferences.onGet.returns(Preferences())
        fakes.preferences.onPut.fails(Boom())
        let (model, env, recorder) = makeModel(fakes: fakes)
        await model.finish().value
        #expect(model.syncState == .failed)
        #expect(!env.device.onboardingCompleted)
        #expect(!env.device.travellerTypes.isEmpty)
        #expect(recorder.outcomes.isEmpty)
        model.continueWithoutSyncing()
        #expect(env.device.onboardingCompleted)
        #expect(!env.device.travellerTypes.isEmpty)
        #expect(recorder.outcomes == [.completed])
    }

    @Test func test_retryAfterFailureSucceeds() async {
        let fakes = FakeRepositories()
        fakes.preferences.onGet.returns(Preferences())
        fakes.preferences.onPut.fails(Boom())
        let (model, env, _) = makeModel(fakes: fakes)
        await model.finish().value
        fakes.preferences.onPut.handler = { $0 }
        await model.retrySync().value
        #expect(model.syncState == .idle)
        #expect(env.device.onboardingCompleted)
    }

    @Test func test_fromSettingsSkipsNotifications() {
        let (model, _, _) = makeModel(fromSettings: true)
        #expect(!model.steps.contains(.notifications))
        model.next()
        while model.step == .howYouTravel { model.next() }
        #expect(model.step == .homeAndPassport)
        model.next()
        #expect(model.step == .firstTrip)
        #expect(model.isLastStep)
    }

    @Test func test_notificationsAskOnlyAfterAllow() async {
        var asked = 0
        let env = AppEnvironment.fake()
        env.device.onboardingStep = OnboardingStep.notifications.rawValue
        let model = OnboardingModel(env: env, fromSettings: false, track: { _ in }, requestNotifications: {
            asked += 1
            return true
        })
        #expect(asked == 0)
        await model.allowNotifications()
        #expect(asked == 1)
        #expect(env.device.reminderOptIn)
        #expect(model.step == .firstTrip)
    }
}
