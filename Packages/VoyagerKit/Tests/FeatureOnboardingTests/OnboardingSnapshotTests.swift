import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureOnboarding

@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    private let configs = [
        SnapshotConfig(name: "se-de", device: .iPhoneSe(.portrait), dark: false, language: .de),
        SnapshotConfig(name: "se-de-dark", device: .iPhoneSe(.portrait), dark: true, language: .de),
        SnapshotConfig.padLight,
        SnapshotConfig.padDark,
    ]

    private func model(step: OnboardingStep, quizPages: Int = 0) -> OnboardingModel {
        let env = AppEnvironment.fake()
        env.device.onboardingCompleted = false
        env.device.onboardingStep = step.rawValue
        let model = OnboardingModel(env: env, fromSettings: false, track: { _ in }, requestNotifications: { false })
        for _ in 0..<quizPages { model.next() }
        return model
    }

    private func snap(_ name: String, step: OnboardingStep, quizPages: Int = 0, prepare: (OnboardingModel) -> Void = { _ in },
        testName: String = #function) async {
        await assertSnapshots(
            of: {
                let built = model(step: step, quizPages: quizPages)
                prepare(built)
                return OnboardingView(model: built)
            }, named: name, configs: configs, layout: .screen, testName: testName)
    }

    func test_welcome() async { await snap("welcome", step: .welcome) }

    func test_quizQuestion() async { await snap("quiz", step: .howYouTravel) }

    func test_quizMultiChoice() async {
        await snap("quiz-interests", step: .howYouTravel, quizPages: 2) { model in
            if let question = model.currentQuestion, let option = question.options.first {
                model.toggle(option, in: question)
            }
        }
    }

    func test_travellerTypeResult() async {
        await snap("result", step: .howYouTravel, quizPages: 6) { _ in }
    }

    func test_homeAndPassport() async {
        await snap("home", step: .homeAndPassport) { model in
            model.choose(airport: AirportSuggestion(iataCode: "FRA", city: "Frankfurt", country: "Germany"))
        }
    }

    func test_notifications() async { await snap("notifications", step: .notifications) }

    func test_firstTrip() async { await snap("first-trip", step: .firstTrip) }
}
