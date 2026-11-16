import AuthCore
import Networking
import SnapshotTesting
import SwiftUI
import TestSupport
import UIKit
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeaturePlay

/// Canvas heights are measured from the recorded PNGs (content bottom plus the screen's own padding), never padded.
@MainActor
final class PlaySnapshotTests: XCTestCase {
    private func phone(
        _ name: String, dark: Bool = false, language: AppLanguage = .en, size: UIContentSizeCategory = .large, height: CGFloat
    ) -> SnapshotConfig {
        SnapshotConfig(
            name: name, device: .iPhoneSe(.portrait), dark: dark, language: language, size: size,
            canvas: CGSize(width: 320, height: height))
    }

    private func pad(_ name: String, height: CGFloat) -> SnapshotConfig {
        SnapshotConfig(name: name, device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: height))
    }

    private func env(_ fakes: FakeRepositories) -> AppEnvironment {
        AppEnvironment.fake(
            user: User(username: "sam"), fakes: fakes, clientConfig: ClientConfig(features: ["play": .number(1), "game": .number(1)]))
    }

    private let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
    private let sleepForever: @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3600)) }

    // MARK: Hub

    private let busyState = PlayState(
        daily: DailyQuizState(available: true, streak: QuizStreak(current: 4, longest: 9, freezeAvailable: true)),
        packs: [
            QuizPack(id: "flags", questions: 40), QuizPack(id: "capitals", questions: 40), QuizPack(id: "landmarks", questions: 30),
            QuizPack(id: "cuisine", questions: 30),
        ],
        challenge: PlayChallenge(id: "2026-W46:JP", kind: .destination, country: "JP", titleKey: "play.challenge.destination"), openH2H: 2)
    private let games = [
        QuizHistoryEntry(sessionID: "a", mode: "daily", score: 540, correct: 4),
        QuizHistoryEntry(sessionID: "b", mode: "pack", pack: "cuisine", score: 410, correct: 3),
        QuizHistoryEntry(sessionID: "c", mode: "challenge", score: 650, correct: 5),
    ]

    private func hub(_ state: PlayState, history: [QuizHistoryEntry] = []) async -> PlayHomeModel {
        let fakes = FakeRepositories()
        fakes.play.onState.returns(state)
        fakes.play.onHistory.returns(history)
        let model = PlayHomeModel(env: env(fakes), track: { _ in })
        await model.load()
        return model
    }

    func test_hubFull() async {
        let model = await hub(busyState, history: games)
        await assertSnapshots(
            of: { PlayHomeView(model: model) }, named: "hub",
            configs: [phone("se-light", height: 808), phone("se-dark", dark: true, height: 808), pad("ipad-light", height: 658)],
            layout: .screen)
    }

    func test_hubDailyDone() async {
        var state = busyState
        state.daily = DailyQuizState(available: false, done: true, score: 540, streak: QuizStreak(current: 5, longest: 9))
        state.challenge = PlayChallenge(id: "w", kind: .featured, done: true)
        state.openH2H = 0
        let model = await hub(state)
        await assertSnapshots(
            of: { PlayHomeView(model: model) }, named: "done", configs: [phone("se-light", height: 561)], layout: .screen)
    }

    func test_hubHindi() async {
        let model = await hub(busyState, history: games)
        await assertSnapshots(
            of: { PlayHomeView(model: model) }, named: "hi", configs: [phone("se-hi", language: .hi, height: 808)], layout: .screen)
    }

    func test_hubGermanAX5() async {
        let model = await hub(busyState, history: games)
        await assertSnapshots(
            of: { PlayHomeView(model: model) }, named: "ax5",
            configs: [phone("se-de-ax5", language: .de, size: ax5, height: 2493)], layout: .screen)
    }

    func test_hubHidden() async {
        let fakes = FakeRepositories()
        fakes.play.onState.fails(APIError.forbidden("game_hidden"))
        let model = PlayHomeModel(env: env(fakes), track: { _ in })
        await model.load()
        await assertSnapshots(
            of: { PlayHomeView(model: model) }, named: "hidden", configs: [phone("se-light", height: 204)], layout: .screen)
    }

    // MARK: Quiz

    private func options(_ names: [(String, String)]) -> [PlayOption] {
        zip(["a", "b", "c", "d"], names).map { PlayOption(id: $0, label: $1.0, code: $1.1) }
    }

    private let flagQuestion = PlayQuestion(
        index: 1, kind: "flag", template: .flag, prompt: .object(["template": .string("flag"), "flag": .string("🇯🇵")]),
        options: [
            PlayOption(id: "a", label: "South Korea", code: "KR"), PlayOption(id: "b", label: "Japan", code: "JP"),
            PlayOption(id: "c", label: "China", code: "CN"), PlayOption(id: "d", label: "Vietnam", code: "VN"),
        ])
    private let capitalQuestion = PlayQuestion(
        index: 1, kind: "capital_of", template: .capitalOf,
        prompt: .object(["template": .string("capital_of"), "country": .string("Australia"), "code": .string("AU")]),
        options: [
            PlayOption(id: "a", label: "Sydney"), PlayOption(id: "b", label: "Canberra"), PlayOption(id: "c", label: "Melbourne"),
            PlayOption(id: "d", label: "Wellington"),
        ])

    private func quiz(_ question: PlayQuestion, result: AnswerResult? = nil, pick: String? = nil)
        async -> QuizModel
    {
        let fakes = FakeRepositories()
        let others = (0..<5).map { index in
            PlayQuestion(index: index, kind: question.kind, template: question.template, prompt: question.prompt, options: question.options)
        }
        let questions = others.map { $0.index == 1 ? question : $0 }
        fakes.play.onSession.returns(
            QuizSession(sessionID: "s1", questions: questions, answers: [GivenAnswer(index: 0, choice: "a", correct: true, points: 120)]))
        if let result { fakes.play.onAnswer.returns(result) }
        let model = QuizModel(env: env(fakes), sessionID: "s1", sleep: sleepForever, track: { _ in })
        await model.load()
        if let pick, let option = question.options.first(where: { $0.id == pick }) { await model.pick(option) }
        model.stopTimer()
        return model
    }

    func test_questionFlag() async {
        let model = await quiz(flagQuestion)
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "flag",
            configs: [phone("se-light", height: 587), phone("se-dark", dark: true, height: 587), pad("ipad-light", height: 566)],
            layout: .screen)
    }

    func test_revealWrong() async {
        let model = await quiz(
            flagQuestion, result: AnswerResult(correct: false, correctChoice: "b", points: 0, elapsedMs: 6100), pick: "a")
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "wrong",
            configs: [phone("se-light", height: 697), phone("se-dark", dark: true, height: 697)], layout: .screen)
    }

    func test_revealCorrect() async {
        let model = await quiz(
            capitalQuestion, result: AnswerResult(correct: true, correctChoice: "b", points: 138, elapsedMs: 1900), pick: "b")
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "correct", configs: [phone("se-light", height: 578)], layout: .screen)
    }

    func test_questionGermanAX5() async {
        let model = await quiz(capitalQuestion)
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "ax5",
            configs: [phone("se-de-ax5", language: .de, size: ax5, height: 734)], layout: .screen)
    }

    func test_questionHindi() async {
        let model = await quiz(flagQuestion)
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "hi", configs: [phone("se-hi", language: .hi, height: 562)], layout: .screen)
    }

    func test_unsupportedQuestion() async {
        let odd = PlayQuestion(
            index: 1, kind: "music_clip", template: .unknown("music_clip"),
            options: [PlayOption(id: "a", label: "x"), PlayOption(id: "b", label: "y")])
        let model = await quiz(odd)
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "unsupported", configs: [phone("se-light", height: 212)], layout: .screen)
    }

    private func summaryModel(language: AppLanguage = .en) async -> QuizModel {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(
            QuizSession(
                sessionID: "s1", questions: [flagQuestion], done: true,
                summary: QuizSummary(
                    score: 640, correct: 4, total: 5, xp: GameDelta(xp: 120, awards: [.init(rule: "quiz_daily", points: 10)]),
                    streak: QuizStreak(current: 5, longest: 9))))
        let model = QuizModel(env: env(fakes), sessionID: "s1", sleep: sleepForever, track: { _ in })
        await model.load()
        return model
    }

    func test_summary() async {
        let model = await summaryModel()
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "summary",
            configs: [phone("se-light", height: 316), phone("se-dark", dark: true, height: 316)], layout: .screen)
    }

    func test_summaryGermanAX5() async {
        let model = await summaryModel()
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "summaryAX5",
            configs: [phone("se-de-ax5", language: .de, size: ax5, height: 674)], layout: .screen)
    }

    func test_expired() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.fails(
            APIError.client(status: 410, detail: "x", code: "session_expired", body: .object(["error_code": .string("session_expired")])))
        let model = QuizModel(env: env(fakes), sessionID: "s1", sleep: sleepForever, track: { _ in })
        await model.load()
        await assertSnapshots(
            of: { QuizView(model: model) }, named: "expired", configs: [phone("se-light", height: 149)], layout: .screen)
    }
}
