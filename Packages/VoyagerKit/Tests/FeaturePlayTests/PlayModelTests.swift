import AuthCore
import Foundation
import L10n
import Networking
@testable import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeaturePlay

@MainActor
struct PlayModelTests {
    final class Events {
        var all: [TelemetryEvent] = []
        var names: [String] { all.map(\.wire.name) }
        var last: WireEvent? { all.last?.wire }
    }

    private func env(_ fakes: FakeRepositories = FakeRepositories(), play: Bool = true) -> AppEnvironment {
        AppEnvironment.fake(
            user: User(username: "sam"), fakes: fakes,
            clientConfig: ClientConfig(features: ["play": .number(play ? 1 : 0), "game": .number(1)]))
    }

    private func clientError(_ status: Int, _ code: String) -> APIError {
        .client(status: status, detail: "x", code: code, body: .object(["error_code": .string(code)]))
    }

    private func question(_ index: Int, template: PromptTemplate = .flag) -> PlayQuestion {
        PlayQuestion(
            index: index, kind: "flag", template: template, prompt: .object(["flag": .string("🇫🇷"), "template": .string("flag")]),
            options: [
                PlayOption(id: "a", label: "France", code: "FR"), PlayOption(id: "b", label: "Italy", code: "IT"),
                PlayOption(id: "c", label: "Spain", code: "ES"), PlayOption(id: "d", label: "Japan", code: "JP"),
            ])
    }

    private func session(
        answers: [GivenAnswer] = [], count: Int = 3, done: Bool = false, summary: QuizSummary? = nil, mode: String = "daily"
    ) -> QuizSession {
        QuizSession(
            sessionID: "s1", mode: mode, questions: (0..<count).map { question($0) }, answers: answers, done: done, summary: summary)
    }

    // MARK: Hub

    @Test func test_loadShowsServerState() async {
        let fakes = FakeRepositories()
        fakes.play.onState.returns(
            PlayState(
                daily: DailyQuizState(available: true, streak: QuizStreak(current: 3, longest: 5, freezeAvailable: true)),
                packs: [QuizPack(id: "flags", questions: 40)], openH2H: 2))
        fakes.play.onHistory.returns([QuizHistoryEntry(sessionID: "h", mode: "daily", score: 420, correct: 4)])
        let events = Events()
        let model = PlayHomeModel(env: env(fakes), track: { events.all.append($0) })
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.daily.streak.current == 3 && model.packs.count == 1 && model.openMatches == 2)
        #expect(model.history.count == 1)
        #expect(events.names == ["play_state_view", "play_board_view"])
    }

    @Test func test_flagOffCallsNothing() async {
        let fakes = FakeRepositories()
        let model = PlayHomeModel(env: env(fakes, play: false))
        await model.load()
        #expect(model.phase == .unavailable(gameHidden: false))
        #expect(fakes.play.onState.callCount == 0)
    }

    @Test func test_gameHiddenAnswerTurnsPlayOffWholly() async {
        let fakes = FakeRepositories()
        fakes.play.onState.fails(APIError.forbidden("Play is hidden: game_hidden"))
        let environment = env(fakes)
        let model = PlayHomeModel(env: environment)
        await model.load()
        #expect(model.phase == .unavailable(gameHidden: true))
        #expect(environment.play.isAvailable == false)
    }

    @Test func test_startDailyOpensTheQuizAndTracksTheMode() async {
        let fakes = FakeRepositories()
        fakes.play.onStartQuiz.returns(session())
        let events = Events()
        let environment = env(fakes)
        let model = PlayHomeModel(env: environment, track: { events.all.append($0) })
        await model.load()
        await model.startDaily()
        #expect(environment.recordedRoutes == [.quiz(sessionID: "s1")])
        #expect(fakes.play.onStartQuiz.lastCall?.mode == .daily)
        #expect(events.last?.name == "play_quiz_start")
        #expect(events.last?.props["mode"] == .string("daily") && events.last?.props["pack"] == .string("none"))
    }

    @Test func test_startPackSendsThePack() async {
        let fakes = FakeRepositories()
        fakes.play.onStartQuiz.returns(session(mode: "pack"))
        let events = Events()
        let model = PlayHomeModel(env: env(fakes), track: { events.all.append($0) })
        await model.startPack(QuizPack(id: "cuisine"))
        #expect(fakes.play.onStartQuiz.lastCall?.pack == "cuisine")
        #expect(events.last?.props["mode"] == .string("pack") && events.last?.props["pack"] == .string("cuisine"))
    }

    @Test func test_alreadyDoneSaysSoAndReloadsTheCard() async {
        let fakes = FakeRepositories()
        fakes.play.onStartQuiz.fails(clientError(409, "already_done"))
        let environment = env(fakes)
        let model = PlayHomeModel(env: environment)
        await model.load()
        await model.startDaily()
        #expect(model.errorText == L10n.text(K.play.quiz.alreadyDone))
        #expect(fakes.play.onState.callCount == 2)
        #expect(environment.recordedRoutes.isEmpty)
    }

    // MARK: Quiz

    private func quiz(_ fakes: FakeRepositories, events: Events = Events()) -> QuizModel {
        QuizModel(
            env: env(fakes), sessionID: "s1", sleep: { _ in try await Task.sleep(for: .seconds(3600)) },
            track: { events.all.append($0) })
    }

    @Test func test_loadResumesAtTheFirstUnansweredQuestion() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session(answers: [GivenAnswer(index: 0), GivenAnswer(index: 1)]))
        let model = quiz(fakes)
        await model.load()
        #expect(model.phase == .question)
        #expect(model.position == 2 && model.isLast)
        model.stopTimer()
    }

    @Test func test_summaryOffersShareOnlyWithSharingAndOpensTheQuizSheet() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session(done: true, summary: QuizSummary(score: 430, correct: 4, total: 5)))
        let off = quiz(fakes)
        await off.load()
        #expect(off.phase == .summary && !off.canShare)  // no Sharing 2.0 on this server
        let sharing = AppEnvironment.fake(
            user: User(username: "sam"), fakes: fakes,
            clientConfig: ClientConfig(features: ["play": .number(1), "game": .number(1), "sharing": .number(1)]))
        let on = QuizModel(env: sharing, sessionID: "s1", sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, track: { _ in })
        await on.load()
        #expect(on.canShare)
        on.share()
        #expect(sharing.recordedRoutes == [.shareSheet(.quiz(sessionID: "s1"))])
    }

    @Test func test_loadOfAFinishedSessionShowsItsSummary() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session(done: true, summary: QuizSummary(score: 430, correct: 4, total: 5)))
        let model = quiz(fakes)
        await model.load()
        #expect(model.phase == .summary)
        #expect(model.summary?.score == 430)
    }

    @Test func test_answerShowsTheServersResultAndTracksTheElapsedSeconds() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session())
        fakes.play.onAnswer.returns(AnswerResult(correct: false, correctChoice: "b", points: 0, elapsedMs: 4200))
        let events = Events()
        let model = quiz(fakes, events: events)
        await model.load()
        await model.pick(PlayOption(id: "a", label: "France", code: "FR"))
        #expect(model.result?.correctChoice == "b" && model.selected == "a")
        #expect(fakes.play.onAnswer.lastCall?.index == 0 && fakes.play.onAnswer.lastCall?.choice == "a")
        #expect(events.names == ["play_quiz_answer"])
        #expect(events.last?.props["elapsed_s"] == .number(4) && events.last?.props["correct"] == .bool(false))
        // A second tap on the same question is ignored.
        await model.pick(PlayOption(id: "b", label: "Italy", code: "IT"))
        #expect(fakes.play.onAnswer.callCount == 1)
        model.next()
        #expect(model.position == 1 && model.result == nil && model.selected == nil)
        model.stopTimer()
    }

    @Test func test_lastAnswerLeadsToTheSummaryWithServerXP() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session(answers: [GivenAnswer(index: 0), GivenAnswer(index: 1)]))
        let summary = QuizSummary(
            score: 540, correct: 4, total: 5, xp: GameDelta(xp: 30, awards: [.init(rule: "quiz_daily", points: 10)]),
            streak: QuizStreak(current: 2))
        fakes.play.onAnswer.returns(AnswerResult(correct: true, correctChoice: "a", points: 140, done: true, summary: summary))
        let events = Events()
        let model = quiz(fakes, events: events)
        await model.load()
        await model.pick(PlayOption(id: "a", label: "France", code: "FR"))
        #expect(model.phase == .question)
        model.next()
        #expect(model.phase == .summary && model.summary?.score == 540 && model.xpEarned == 10)
        #expect(events.last?.name == "play_quiz_done")
        #expect(events.last?.props["correct"] == .number(4) && events.last?.props["mode"] == .string("daily"))
    }

    @Test func test_lastAnswerWithoutSummaryFetchesTheSession() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session(answers: [GivenAnswer(index: 0), GivenAnswer(index: 1)]))
        let model = quiz(fakes)
        await model.load()
        fakes.play.onSession.returns(session(done: true, summary: QuizSummary(score: 300, correct: 3, total: 5)))
        fakes.play.onAnswer.returns(AnswerResult(correct: true, correctChoice: "a", points: 100, done: true))
        await model.pick(PlayOption(id: "a", label: "France", code: "FR"))
        model.next()
        #expect(model.summary?.score == 300)
    }

    @Test func test_failedAnswerKeepsTheQuestionOpen() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session())
        fakes.play.onAnswer.fails(APIError.network)
        let model = quiz(fakes)
        await model.load()
        await model.pick(PlayOption(id: "a", label: "France", code: "FR"))
        #expect(model.phase == .question && model.result == nil && model.selected == nil)
        #expect(model.errorText != nil)
        fakes.play.onAnswer.returns(AnswerResult(correct: true, correctChoice: "a", points: 100))
        await model.pick(PlayOption(id: "a", label: "France", code: "FR"))
        #expect(model.result?.correct == true && model.errorText == nil)
        model.stopTimer()
    }

    @Test func test_expiredSessionEndsTheQuiz() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session())
        fakes.play.onAnswer.fails(clientError(410, "session_expired"))
        let model = quiz(fakes)
        await model.load()
        await model.pick(PlayOption(id: "a", label: "France", code: "FR"))
        #expect(model.phase == .failed(message: L10n.text(K.play.quiz.expired), retryable: false))
    }

    @Test func test_unsupportedQuestionIsNeverAnswered() async {
        let fakes = FakeRepositories()
        let odd = PlayQuestion(index: 0, template: .unknown("music_clip"), options: [PlayOption(id: "a", label: "x")])
        fakes.play.onSession.returns(QuizSession(sessionID: "s1", questions: [odd]))
        let model = quiz(fakes)
        await model.load()
        #expect(model.question?.isSupported == false)
        await model.pick(PlayOption(id: "a", label: "x"))
        #expect(fakes.play.onAnswer.callCount == 0)
        model.stopTimer()
    }

    @Test func test_countdownRunsDownButNeverBlocksAnAnswer() async {
        let fakes = FakeRepositories()
        fakes.play.onSession.returns(session())
        fakes.play.onAnswer.returns(AnswerResult(correct: true, correctChoice: "a", points: 100))
        let model = QuizModel(env: env(fakes), sessionID: "s1", sleep: { _ in await Task.yield() }, track: { _ in })
        await model.load()
        await model.timerTask?.value
        #expect(model.secondsLeft == 0)
        await model.pick(PlayOption(id: "a", label: "France", code: "FR"))
        #expect(model.result?.correct == true)
    }

    @Test func test_playOffTurnsTheQuizUnavailable() async {
        let fakes = FakeRepositories()
        let model = QuizModel(env: env(fakes, play: false), sessionID: "s1", track: { _ in })
        await model.load()
        #expect(model.phase == .unavailable)
        #expect(fakes.play.onSession.callCount == 0)
    }

    // MARK: Text

    @Test func test_countryNamesFollowTheOptionCode() {
        #expect(QuizText.optionLabel(PlayOption(id: "a", label: "Frankreich", code: "FR")) == "France")
        #expect(QuizText.optionLabel(PlayOption(id: "a", label: "Paris")) == "Paris")
        let capital = PlayQuestion(
            index: 0, template: .capitalOf, prompt: .object(["country": .string("Japan"), "code": .string("JP")]),
            options: [PlayOption(id: "a", label: "Tokyo"), PlayOption(id: "b", label: "Kyoto")])
        #expect(QuizText.prompt(capital) == "What is the capital of Japan?")
        let unknown = PlayQuestion(index: 0, template: .unknown("x"), options: [])
        #expect(QuizText.prompt(unknown) == nil)
    }
}
