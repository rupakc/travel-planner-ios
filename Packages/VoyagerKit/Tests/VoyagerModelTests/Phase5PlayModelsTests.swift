import Foundation
import Testing

@testable import VoyagerModel

private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
}

/// Every example of the Play section of `Social-API.md`, plus the lenient-decoding rules.
@Suite struct Phase5PlayModelsTests {
    @Test func test_playStateExample() throws {
        let state = try decode(
            PlayState.self,
            """
            {"daily": {"available": true, "done": false, "score": null, "streak": {"current": 3, "longest": 9, "freeze_available": true}},
             "packs": [{"id": "flags", "title_key": "play.pack.flags", "questions": 40}, {"id": "capitals", "questions": 30}, {}],
             "challenge": {"id": "2026-W46:JP", "kind": "destination", "country": "JP", "title_key": "play.challenge.destination", "done": false},
             "open_h2h": 2}
            """)
        #expect(state.daily.available && !state.daily.done && state.daily.score == nil)
        #expect(state.daily.streak == QuizStreak(current: 3, longest: 9, freezeAvailable: true))
        #expect(state.packs.map(\.id) == ["flags", "capitals"] && state.packs[0].questions == 40 && state.packs[1].titleKey == nil)
        #expect(state.challenge == PlayChallenge(
            id: "2026-W46:JP", kind: .destination, country: "JP", titleKey: "play.challenge.destination", done: false))
        #expect(state.openH2H == 2)
    }

    @Test func test_playStateMinimalAndNullChallenge() throws {
        let state = try decode(PlayState.self, #"{"daily": {"available": false, "done": true, "score": 400}, "packs": [], "challenge": null}"#)
        #expect(state.daily.done && state.daily.score == 400 && state.daily.streak == QuizStreak())
        #expect(state.challenge == nil && state.openH2H == 0)
        #expect(try decode(PlayState.self, "{}") == PlayState())
        #expect(try decode(PlayChallenge.self, #"{"id": "w:X", "kind": "bonus"}"#).kind == .unknown("bonus"))
    }

    private let sessionJSON = """
        {"session_id": "s1", "mode": "pack", "pack": "flags", "expires_at": "2026-11-14T10:20:00Z", "resumed": false,
         "questions": [
           {"index": 1, "kind": "flag", "prompt": {"template": "capital_of", "capital": "Lima"},
            "options": [{"id": "a", "label": "Peru", "code": "PE"}, {"id": "b", "label": "Chile", "code": "CL"}]},
           {"index": 0, "kind": "flag", "prompt": {"template": "flag", "code": "JP"},
            "options": [{"id": "a", "label": "Japan", "code": "JP"}, {"id": "b", "label": "Laos", "code": "LA"},
                        {"id": "c", "label": "Chad", "code": "TD"}, {"id": "d", "label": "Fiji", "code": "FJ"}]}]}
        """

    @Test func test_quizSessionExample() throws {
        let session = try decode(QuizSession.self, sessionJSON)
        #expect(session.sessionID == "s1" && session.mode == "pack" && session.pack == "flags" && session.matchID == nil)
        #expect(session.questions.map(\.index) == [0, 1])
        #expect(session.questions[0].template == .flag && session.questions[0].options.map(\.id) == ["a", "b", "c", "d"])
        #expect(session.questions[0].options[0].code == "JP" && session.questions[1].prompt["capital"].string == "Lima")
        #expect(session.answers.isEmpty && !session.done && session.summary == nil && session.firstUnanswered?.index == 0)
    }

    @Test func test_resumeContinuesAtFirstUnanswered() throws {
        let session = try decode(
            QuizSession.self,
            """
            {"session_id": "s2", "mode": "daily", "resumed": true, "done": false,
             "answers": [{"index": 0, "choice": "a", "correct": true, "correct_choice": "a", "points": 140}, {"index": 1}, {"nope": 1}],
             "questions": [{"index": 0, "prompt": {"template": "flag"}, "options": [{"id": "a", "label": "x"}, {"id": "b", "label": "y"}]},
                           {"index": 1, "prompt": {"template": "flag"}, "options": [{"id": "a", "label": "x"}, {"id": "b", "label": "y"}]},
                           {"index": 2, "prompt": {"template": "flag"}, "options": [{"id": "a", "label": "x"}, {"id": "b", "label": "y"}]}]}
            """)
        #expect(session.resumed && session.answers.map(\.index) == [0, 1] && session.answers[0].points == 140)
        #expect(session.firstUnanswered?.index == 2)
        let finished = QuizSession(sessionID: "s", questions: session.questions, answers: session.questions.map { GivenAnswer(index: $0.index) })
        #expect(finished.firstUnanswered == nil)
    }

    @Test func test_unknownQuestionKindDegrades() throws {
        let session = try decode(
            QuizSession.self,
            """
            {"session_id": "s3", "mode": "daily",
             "questions": [{"index": 0, "kind": "audio", "prompt": {"template": "name_that_tune"},
                            "options": [{"id": "a", "label": "x"}, {"id": "b", "label": "y"}]},
                           {"index": 1, "kind": "flag", "prompt": {"template": "dish_country", "dish": "Ramen"},
                            "options": [{"id": "a", "label": "x"}, {"id": "b", "label": "y"}]},
                           {"index": 2, "kind": "flag", "prompt": {"template": "flag"}, "options": [{"id": "a", "label": "only"}]}]}
            """)
        #expect(session.questions.count == 3)
        #expect(session.questions[0].template == .unknown("name_that_tune") && !session.questions[0].isSupported)
        #expect(session.questions[1].template == .dishCountry && session.questions[1].isSupported)
        #expect(!session.questions[2].isSupported)
        #expect(PromptTemplate(rawValue: "country_of_capital") == .countryOfCapital && PromptTemplate(rawValue: "landmark_country") == .landmarkCountry)
    }

    @Test func test_answerResultAndSummary() throws {
        let result = try decode(
            AnswerResult.self,
            """
            {"correct": true, "correct_choice": "b", "points": 132, "elapsed_ms": 2400, "done": true,
             "summary": {"score": 612, "correct": 5, "total": 5,
                         "xp": {"xp": 25, "awards": [{"rule": "quiz_daily", "points": 10}, {"rule": "quiz_perfect", "points": 20}],
                                "badges": [], "level_up": null},
                         "streak": {"current": 4, "longest": 9, "freeze_available": false}}}
            """)
        #expect(result.correct && result.correctChoice == "b" && result.points == 132 && result.elapsedMs == 2400 && result.done)
        #expect(result.summary?.score == 612 && result.summary?.correct == 5 && result.summary?.total == 5)
        #expect(result.summary?.xp?.awards.count == 2 && result.summary?.streak?.current == 4)
        let mid = try decode(AnswerResult.self, #"{"correct": false, "correct_choice": "a", "points": 0, "elapsed_ms": 900, "done": false}"#)
        #expect(!mid.correct && !mid.done && mid.summary == nil)
        #expect(throws: DecodingError.self) { try decode(AnswerResult.self, #"{"points": 3}"#) }
    }

    @Test func test_summaryWithoutXpWhenTheGameIsHidden() throws {
        let result = try decode(
            AnswerResult.self,
            #"{"correct": true, "correct_choice": "a", "points": 100, "done": true, "summary": {"score": 500, "correct": 5, "total": 5}}"#)
        #expect(result.summary?.xp == nil && result.summary?.streak == nil && result.summary?.score == 500)
    }

    @Test func test_historyAcceptsBareListOrWrapper() throws {
        let entry = #"{"session_id": "s1", "mode": "daily", "pack": null, "score": 500, "correct": 4, "finished_at": "2026-11-12T09:00:00Z"}"#
        for text in ["[\(entry), {}]", #"{"history": [\#(entry)]}"#, #"{"sessions": [\#(entry)]}"#] {
            let history = try decode(QuizHistory.self, text)
            #expect(history.entries.map(\.sessionID) == ["s1"] && history.entries[0].score == 500 && history.entries[0].pack == nil)
        }
        #expect(try decode(QuizHistory.self, "{}").entries.isEmpty)
        #expect(throws: DecodingError.self) { try decode(QuizHistory.self, "7") }
    }

    @Test func test_h2hStatesMapped() throws {
        let list = try decode(
            H2HList.self,
            """
            {"matches": [
              {"id": "m1", "opponent": {"handle": "a"}, "pack": "flags", "state": "waiting_you", "you": null, "them": null, "winner": null, "expires_at": "x", "session_id": "s1"},
              {"id": "m2", "opponent": {"handle": "b"}, "state": "waiting_them", "you": 400, "them": null, "winner": null},
              {"id": "m3", "opponent": {"handle": "c"}, "state": "done", "you": 500, "them": 450, "winner": "you"},
              {"id": "m4", "opponent": {"handle": "d"}, "state": "declined"}, {"id": "m5", "opponent": {"handle": "e"}, "state": "expired"},
              {"id": "m6", "opponent": {"handle": "f"}, "state": "rematch"}, {"id": "m7"}]}
            """)
        #expect(list.matches.map(\.id) == ["m1", "m2", "m3", "m4", "m5", "m6"])
        #expect(list.matches.map(\.state) == [.waitingYou, .waitingThem, .done, .declined, .expired, .unknown("rematch")])
        #expect(list.matches[2].them == 450 && list.matches[2].winner == .you && list.matches[0].sessionID == "s1")
    }

    @Test func test_opponentScoreHiddenUntilDone() throws {
        let leaked = try decode(
            H2HMatch.self,
            #"{"id": "m1", "opponent": {"handle": "a"}, "state": "waiting_them", "you": 300, "them": 999, "winner": "them"}"#)
        #expect(leaked.you == 300 && leaked.them == nil && leaked.winner == nil)
        let draw = try decode(H2HMatch.self, #"{"id": "m2", "opponent": {"handle": "a"}, "state": "done", "you": 5, "them": 5, "winner": "draw"}"#)
        #expect(draw.winner == .draw && draw.them == 5)
    }

    @Test func test_h2hCreateAnswerIsASessionWithTheMatchID() throws {
        let session = try decode(
            QuizSession.self,
            #"{"id": "m9", "session_id": "s9", "mode": "h2h", "resumed": true, "questions": []}"#)
        #expect(session.matchID == "m9" && session.sessionID == "s9" && session.mode == "h2h" && session.resumed)
    }

    @Test func test_leaderboardExample() throws {
        let board = try decode(
            Leaderboard.self,
            """
            {"week": "2026-W46", "rows": [{"rank": 1, "handle": "a", "score": 900, "level": 5, "you": false},
                                           {"rank": 2, "handle": "me", "score": 800, "you": true}, {"handle": "x"}],
             "you": {"rank": 2, "score": 800, "opted_in": true}}
            """)
        #expect(board.week == "2026-W46" && board.rows.map(\.handle) == ["a", "me"] && board.rows[0].level == 5)
        #expect(board.rows[1].isYou && board.rows[1].level == nil && board.you == BoardYou(rank: 2, score: 800, optedIn: true))
        let off = try decode(Leaderboard.self, #"{"week": "2026-W45", "rows": [], "you": {"rank": null, "score": 0, "opted_in": false}}"#)
        #expect(off.you?.rank == nil && off.you?.optedIn == false)
        #expect(try decode(Leaderboard.self, #"{"week": "w", "rows": [], "you": null}"#).you == nil)
    }

    @Test func test_startEncodesPackOnlyForPackMode() throws {
        func json(_ start: QuizStart) throws -> JSONValue {
            try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(start))
        }
        let pack = try json(QuizStart(mode: .pack, pack: "flags", locale: "de"))
        #expect(pack["mode"].string == "pack" && pack["pack"].string == "flags" && pack["locale"].string == "de")
        let daily = try json(QuizStart(mode: .daily, pack: "flags"))
        #expect(daily["mode"].string == "daily" && daily["pack"].isNull && daily["locale"].isNull)
        #expect(try json(QuizStart(mode: .challenge))["mode"].string == "challenge")
    }

    @Test func test_boardScopesAndWeeksMatchTheContract() {
        #expect(BoardScope.allCases.map(\.rawValue) == ["global", "friends"])
        #expect(BoardWeek.allCases.map(\.rawValue) == ["current", "previous"])
    }
}
