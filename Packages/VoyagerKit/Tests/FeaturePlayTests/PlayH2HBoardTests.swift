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

/// Head-to-head, the weekly boards and the weekly challenge (Task 5.5).
@MainActor
struct PlayH2HBoardTests {
    final class Events {
        var all: [TelemetryEvent] = []
        var names: [String] { all.map(\.wire.name) }
        var last: WireEvent? { all.last?.wire }
    }

    private func env(_ fakes: FakeRepositories = FakeRepositories(), social: Bool = true) -> AppEnvironment {
        AppEnvironment.fake(
            user: User(username: "sam"), fakes: fakes,
            clientConfig: ClientConfig(features: ["play": .number(1), "game": .number(1), "social": .number(social ? 1 : 0)]))
    }

    private func clientError(_ status: Int, _ code: String) -> APIError {
        .client(status: status, detail: "x", code: code, body: .object(["error_code": .string(code)]))
    }

    private func match(
        _ id: String = "m1", state: H2HState, you: Int? = nil, them: Int? = nil, winner: H2HWinner? = nil, pack: String? = "flags"
    ) -> H2HMatch {
        H2HMatch(id: id, opponent: "mia", pack: pack, state: state, you: you, them: them, winner: winner)
    }

    private func session(_ id: String = "s9") -> QuizSession {
        QuizSession(sessionID: id, matchID: "m1", mode: "h2h", pack: "flags")
    }

    // MARK: States

    @Test func test_h2hStatesMapped() {
        #expect(H2HText.state(.waitingYou) == L10n.text(K.play.h2h.state_waiting_you))
        #expect(H2HText.state(.waitingThem) == L10n.text(K.play.h2h.state_waiting_them))
        #expect(H2HText.state(.done) == L10n.text(K.play.h2h.state_done))
        #expect(H2HText.state(.declined) == L10n.text(K.play.h2h.state_declined))
        #expect(H2HText.state(.expired) == L10n.text(K.play.h2h.state_expired))
        // An unknown state is a plain waiting row.
        #expect(H2HText.state(.unknown("paused")) == L10n.text(K.play.h2h.state_waiting_them))
    }

    @Test func test_opponentScoreHiddenUntilDone() {
        #expect(H2HText.score(match(state: .waitingThem, you: 4, them: 3)) == nil)
        #expect(H2HText.score(match(state: .waitingYou, you: nil, them: 3)) == nil)
        #expect(H2HText.score(match(state: .done, you: 4, them: 3, winner: .you)) == "4 to 3")
        #expect(H2HText.winner(.them) == L10n.text(K.play.h2h.winner_them))
        #expect(H2HText.winner(nil) == L10n.text(K.play.h2h.winner_draw))
    }

    // MARK: Create

    @Test func test_createByHandleStripsTheAtAndOpensTheQuiz() async {
        let fakes = FakeRepositories()
        fakes.play.onChallenge.returns(session())
        let events = Events()
        let environment = env(fakes)
        let model = H2HListModel(env: environment, track: { events.all.append($0) })
        model.handle = "  @mia "
        model.pack = "cuisine"
        #expect(model.canCreate)
        await model.create()
        #expect(fakes.play.onChallenge.lastCall?.handle == "mia" && fakes.play.onChallenge.lastCall?.pack == "cuisine")
        #expect(environment.recordedRoutes == [.quiz(sessionID: "s9")])
        #expect(events.names == ["play_h2h_create", "play_quiz_start"])
        #expect(events.last?.props["mode"] == .string("h2h") && events.last?.props["pack"] == .string("cuisine"))
        #expect(model.handle.isEmpty)
    }

    @Test func test_createNeedsAHandle() async {
        let fakes = FakeRepositories()
        let model = H2HListModel(env: env(fakes), track: { _ in })
        model.handle = " @ "
        #expect(!model.canCreate)
        await model.create()
        #expect(fakes.play.onChallenge.callCount == 0)
    }

    @Test func test_createLimitReachedSaysSo() async {
        let fakes = FakeRepositories()
        fakes.play.onChallenge.fails(clientError(422, "limit_reached"))
        let environment = env(fakes)
        let model = H2HListModel(env: environment, track: { _ in })
        model.handle = "mia"
        await model.create()
        #expect(model.errorText == L10n.text(K.social.errors.limit_reached))
        #expect(environment.recordedRoutes.isEmpty)
    }

    @Test func test_createErrorsAreTranslated() async {
        let fakes = FakeRepositories()
        let model = H2HListModel(env: env(fakes), track: { _ in })
        model.handle = "mia"
        fakes.play.onChallenge.fails(clientError(404, "profile_not_found"))
        await model.create()
        #expect(model.errorText == L10n.text(K.social.errors.profile_not_found))
        fakes.play.onChallenge.fails(clientError(409, "profile_required"))
        await model.create()
        #expect(model.errorText == L10n.text(K.social.errors.profile_required))
        fakes.play.onChallenge.fails(clientError(403, "restricted"))
        await model.create()
        #expect(model.errorText == L10n.text(K.social.errors.restricted))
    }

    @Test func test_listLoadsTheCallersMatches() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match(state: .waitingYou), match("m2", state: .done, you: 4, them: 2, winner: .you)])
        let model = H2HListModel(env: env(fakes), track: { _ in })
        await model.load()
        #expect(model.phase == .loaded && model.matches.count == 2)
    }

    @Test func test_listFailureKeepsTheFormUsable() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.fails(APIError.network)
        let model = H2HListModel(env: env(fakes), track: { _ in })
        await model.load()
        #expect(model.phase == .failed)
        model.handle = "mia"
        #expect(model.canCreate)
    }

    // MARK: One match

    @Test func test_matchOpenedAndResultTrackedOnce() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match(state: .done, you: 4, them: 3, winner: .you)])
        let events = Events()
        let model = H2HMatchModel(env: env(fakes), matchID: "m1", track: { events.all.append($0) })
        await model.load()
        await model.load()
        #expect(model.phase == .loaded)
        #expect(events.names == ["play_h2h_open", "play_h2h_result"])
        #expect(events.last?.props["winner"] == .string("you"))
    }

    @Test func test_matchNotInTheListIsMissing() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match("other", state: .waitingYou)])
        let model = H2HMatchModel(env: env(fakes), matchID: "m1", track: { _ in })
        await model.load()
        #expect(model.phase == .missing)
    }

    @Test func test_acceptPlaysTheOpponentsSession() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match(state: .waitingYou)])
        fakes.play.onAccept.returns(session("s5"))
        let events = Events()
        let environment = env(fakes)
        let model = H2HMatchModel(env: environment, matchID: "m1", track: { events.all.append($0) })
        await model.load()
        #expect(model.canAnswer)
        await model.accept()
        #expect(fakes.play.onAccept.lastCall == "m1")
        #expect(environment.recordedRoutes == [.quiz(sessionID: "s5")])
        #expect(events.names.last == "play_quiz_start" && events.last?.props["mode"] == .string("h2h"))
    }

    @Test func test_creatorWaitingOnOwnQuizContinuesInsteadOfAccepting() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([
            H2HMatch(id: "m1", opponent: "mia", pack: "flags", state: .waitingYou, sessionID: "mine1")
        ])
        let environment = env(fakes)
        let model = H2HMatchModel(env: environment, matchID: "m1", track: { _ in })
        await model.load()
        // Accept and decline would answer 404 / 409 for a caller who already has a session.
        #expect(model.canContinue && !model.canAnswer)
        await model.accept()
        await model.decline()
        #expect(fakes.play.onAccept.callCount == 0 && fakes.play.onDecline.callCount == 0)
        model.resume()
        #expect(environment.recordedRoutes == [.quiz(sessionID: "mine1")])
    }

    @Test func test_invitationWithoutSessionStillAcceptsAndDeclines() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match(state: .waitingYou)])
        let model = H2HMatchModel(env: env(fakes), matchID: "m1", track: { _ in })
        await model.load()
        #expect(model.canAnswer && !model.canContinue)
    }

    @Test func test_onlyAnInvitationCanBeAnswered() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match(state: .waitingThem)])
        let model = H2HMatchModel(env: env(fakes), matchID: "m1", track: { _ in })
        await model.load()
        #expect(!model.canAnswer)
        await model.accept()
        await model.decline()
        #expect(fakes.play.onAccept.callCount == 0 && fakes.play.onDecline.callCount == 0)
    }

    @Test func test_declineClosesTheScreen() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match(state: .waitingYou)])
        let model = H2HMatchModel(env: env(fakes), matchID: "m1", track: { _ in })
        await model.load()
        await model.decline()
        #expect(fakes.play.onDecline.lastCall == "m1" && model.declined)
    }

    @Test func test_expiredMatchSaysSo() async {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match(state: .waitingYou)])
        fakes.play.onAccept.fails(clientError(410, "match_expired"))
        let model = H2HMatchModel(env: env(fakes), matchID: "m1", track: { _ in })
        await model.load()
        await model.accept()
        #expect(model.errorText == L10n.text(K.play.quiz.expired))
    }

    // MARK: Boards

    private func board(you: BoardYou?, rows: [BoardRow] = []) -> Leaderboard {
        Leaderboard(week: "2026-W46", rows: rows, you: you)
    }

    @Test func test_boardOptInPrompt() async {
        let fakes = FakeRepositories()
        let model = BoardModel(env: env(fakes), track: { _ in })
        // Friends scope never asks.
        fakes.play.onLeaderboard.returns(board(you: BoardYou(rank: nil, score: 0, optedIn: false)))
        await model.load()
        #expect(model.optIn == .none)
        // Global, a handle, not opted in: one tap joins.
        await model.select(scope: .global)
        #expect(model.optIn == .join)
        // Global without a profile: create one first.
        fakes.play.onLeaderboard.returns(board(you: nil))
        await model.load()
        #expect(model.optIn == .needsProfile)
        // Opted in: nothing to ask.
        fakes.play.onLeaderboard.returns(board(you: BoardYou(rank: 3, score: 410, optedIn: true)))
        await model.load()
        #expect(model.optIn == .none)
    }

    @Test func test_boardOptInHiddenWithoutSocial() async {
        let fakes = FakeRepositories()
        fakes.play.onLeaderboard.returns(board(you: BoardYou(optedIn: false)))
        let model = BoardModel(env: env(fakes, social: false), track: { _ in })
        await model.select(scope: .global)
        #expect(model.optIn == .none)
    }

    @Test func test_joinSetsTheOptInAndReloads() async {
        let fakes = FakeRepositories()
        fakes.play.onLeaderboard.returns(board(you: BoardYou(optedIn: false)))
        fakes.social.onSaveProfile.returns(OwnProfile(handle: "sam", leaderboardOptIn: true))
        let model = BoardModel(env: env(fakes), track: { _ in })
        await model.select(scope: .global)
        fakes.play.onLeaderboard.returns(board(you: BoardYou(rank: 2, score: 300, optedIn: true)))
        await model.join()
        #expect(fakes.social.onSaveProfile.lastCall?.leaderboardOptIn == true && fakes.social.onSaveProfile.lastCall?.handle == nil)
        #expect(model.optIn == .none && model.mineText == "You are #2 with 300 points")
    }

    @Test func test_boardHandlesOnly() async {
        let fakes = FakeRepositories()
        fakes.play.onLeaderboard.returns(
            board(
                you: nil,
                rows: [
                    BoardRow(rank: 1, handle: "mia", score: 640, level: 4),
                    BoardRow(rank: 2, handle: "sam", score: 410, isYou: true),
                ]))
        let model = BoardModel(env: env(fakes), track: { _ in })
        await model.load()
        #expect(model.line(model.rows[0]) == "1. mia")
        #expect(model.line(model.rows[1]) == "2. sam " + L10n.text(K.play.board.you))
        #expect(model.level(model.rows[0]) != nil && model.level(model.rows[1]) == nil)
    }

    @Test func test_boardViewTracksTheScopeNotTheWeek() async {
        let fakes = FakeRepositories()
        let events = Events()
        let model = BoardModel(env: env(fakes), track: { events.all.append($0) })
        await model.load()
        await model.select(week: .previous)
        await model.select(scope: .global)
        #expect(events.names == ["play_board_view", "play_board_view"])
        #expect(events.all.map { $0.wire.props["scope"] } == [.string("friends"), .string("global")])
        #expect(fakes.play.onLeaderboard.lastCall?.scope == .global && fakes.play.onLeaderboard.lastCall?.week == .previous)
    }

    @Test func test_emptyBoardAndUnranked() async {
        let fakes = FakeRepositories()
        fakes.play.onLeaderboard.returns(board(you: BoardYou(rank: nil, score: 0, optedIn: true)))
        let model = BoardModel(env: env(fakes), track: { _ in })
        await model.load()
        #expect(model.rows.isEmpty && model.showsUnranked && model.mineText == nil)
    }

    @Test func test_boardFailureIsShownNotThrown() async {
        let fakes = FakeRepositories()
        fakes.play.onLeaderboard.fails(APIError.network)
        let model = BoardModel(env: env(fakes), track: { _ in })
        await model.load()
        #expect(model.phase == .failed)
    }

    // MARK: Challenge and the hub

    private func hubState(done: Bool) -> PlayState {
        PlayState(
            daily: DailyQuizState(available: true),
            challenge: PlayChallenge(id: "2026-W46:JP", kind: .destination, country: "JP", done: done))
    }

    @Test func test_challengeStartsAChallengeQuiz() async {
        let fakes = FakeRepositories()
        fakes.play.onState.returns(hubState(done: false))
        fakes.play.onStartQuiz.returns(QuizSession(sessionID: "c1", mode: "challenge"))
        let events = Events()
        let environment = env(fakes)
        let model = PlayHomeModel(env: environment, track: { events.all.append($0) })
        await model.load()
        #expect(events.names.contains("play_challenge_view"))
        await model.startChallenge()
        #expect(fakes.play.onStartQuiz.lastCall?.mode == .challenge)
        #expect(environment.recordedRoutes == [.quiz(sessionID: "c1")])
        #expect(events.last?.props["mode"] == .string("challenge") && events.last?.props["pack"] == .string("none"))
    }

    @Test func test_challengeOncePerWeekDoneState() async {
        let fakes = FakeRepositories()
        fakes.play.onState.returns(hubState(done: true))
        let environment = env(fakes)
        let model = PlayHomeModel(env: environment, track: { _ in })
        await model.load()
        await model.startChallenge()
        #expect(fakes.play.onStartQuiz.callCount == 0 && environment.recordedRoutes.isEmpty)
    }

    @Test func test_challengeAlreadyDoneElsewhereReloadsTheCard() async {
        let fakes = FakeRepositories()
        fakes.play.onState.returns(hubState(done: false))
        fakes.play.onStartQuiz.fails(clientError(409, "already_done"))
        let model = PlayHomeModel(env: env(fakes), track: { _ in })
        await model.load()
        fakes.play.onState.returns(hubState(done: true))
        await model.startChallenge()
        #expect(model.challenge?.done == true && model.errorText == L10n.text(K.play.quiz.alreadyDone))
    }

    @Test func test_gameHidden403() async {
        let fakes = FakeRepositories()
        fakes.play.onState.returns(hubState(done: false))
        fakes.play.onLeaderboard.fails(APIError.forbidden("Play is hidden: game_hidden"))
        let environment = env(fakes)
        let model = PlayHomeModel(env: environment, track: { _ in })
        await model.load()
        #expect(model.phase == .unavailable(gameHidden: true))
        #expect(environment.play.isAvailable == false)
    }

    @Test func test_hubLoadsMatchesAndBoard() async {
        let fakes = FakeRepositories()
        fakes.play.onState.returns(hubState(done: false))
        fakes.play.onMatches.returns([match(state: .waitingYou)])
        let model = PlayHomeModel(env: env(fakes), track: { _ in })
        await model.load()
        #expect(model.h2h.matches.count == 1 && model.board.phase == .loaded)
    }
}
