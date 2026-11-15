import Foundation
import Networking
import Testing
import VoyagerModel

@testable import VoyagerData

struct Phase5DataTests {
    @Test func test_socialRoutes() {
        #expect(Endpoints.socialProfile().path == "/api/social/profile" && Endpoints.socialProfile().auth == .required)
        let save = Endpoints.socialSaveProfile(ProfilePatch(bio: "x"))
        #expect(save.method == .put && save.path == "/api/social/profile")
        let check = Endpoints.socialHandleCheck(" Maria_K ")
        #expect(check.path == "/api/social/handles/check" && check.query == [URLQueryItem(name: "handle", value: "maria_k")])
        #expect(Endpoints.socialPublicProfile(handle: "Maria_K").path == "/api/social/profile/maria_k")
        #expect(Endpoints.socialProfileIdeas(handle: "a", cursor: "7").path == "/api/social/profile/a/ideas")
        #expect(Endpoints.socialProfileIdeas(handle: "a", cursor: "7").query == [URLQueryItem(name: "cursor", value: "7")])
        #expect(Endpoints.socialFollow(handle: "a").method == .put && Endpoints.socialUnfollow(handle: "a").method == .delete)
        #expect(Endpoints.socialFollowRequests().path == "/api/social/follow-requests")
        #expect(Endpoints.socialAcceptRequest(handle: "a").path == "/api/social/follow-requests/a/accept")
        #expect(Endpoints.socialDeclineRequest(handle: "a").method == .post)
        #expect(Endpoints.socialFollowers(cursor: nil).query.isEmpty && Endpoints.socialFollowing(cursor: "").query.isEmpty)
        #expect(Endpoints.socialBlock(handle: "a").method == .put && Endpoints.socialUnblock(handle: "a").method == .delete)
        #expect(Endpoints.socialBlocks().path == "/api/social/blocks")
    }

    @Test func test_ideaAndCommentRoutes() {
        let feed = Endpoints.socialFeed(scope: .forYou, cursor: "20", limit: 99)
        #expect(feed.path == "/api/social/feed")
        #expect(feed.query == [
            URLQueryItem(name: "scope", value: "for_you"), URLQueryItem(name: "cursor", value: "20"),
            URLQueryItem(name: "limit", value: "30"),
        ])
        #expect(Endpoints.socialFeed(scope: .new, cursor: nil, limit: nil).query == [URLQueryItem(name: "scope", value: "new")])
        #expect(Endpoints.socialIdea(id: "i1").path == "/api/social/ideas/i1")
        let publish = Endpoints.socialPublish(IdeaDraft(planID: 1, title: "t"))
        #expect(publish.method == .post && publish.path == "/api/social/ideas")
        #expect(Endpoints.socialDeleteIdea(id: "i1").method == .delete)
        #expect(Endpoints.socialLike(ideaID: "i1", on: true).method == .put && Endpoints.socialLike(ideaID: "i1", on: false).method == .delete)
        #expect(Endpoints.socialLike(ideaID: "i1", on: true).path == "/api/social/ideas/i1/like")
        #expect(Endpoints.socialSave(ideaID: "i1").method == .post && Endpoints.socialForgetSave(ideaID: "i1").method == .delete)
        #expect(Endpoints.socialComments(ideaID: "i1", cursor: "c").path == "/api/social/ideas/i1/comments")
        #expect(Endpoints.socialComment(ideaID: "i1", text: "hi").method == .post)
        #expect(Endpoints.socialDeleteComment(id: "c1").path == "/api/social/comments/c1")
        #expect(Endpoints.socialHelpful(commentID: "c1", on: true).path == "/api/social/comments/c1/helpful")
        #expect(Endpoints.socialHelpful(commentID: "c1", on: false).method == .delete)
        #expect(Endpoints.socialReport(ReportRequest(target: .idea, id: "i1", reason: .spam)).path == "/api/social/reports")
    }

    @Test func test_playRoutes() {
        #expect(Endpoints.playState().path == "/api/play/state")
        #expect(Endpoints.playStartQuiz(QuizStart(mode: .daily)).method == .post)
        #expect(Endpoints.playSession(id: "s1").path == "/api/play/quiz/s1")
        let answer = Endpoints.playAnswer(sessionID: "s1", index: 2, choice: "b")
        #expect(answer.method == .post && answer.path == "/api/play/quiz/s1/answer")
        #expect(Endpoints.playHistory(limit: 10).query == [URLQueryItem(name: "limit", value: "10")])
        #expect(Endpoints.playHistory(limit: nil).query.isEmpty)
        #expect(Endpoints.playMatches().path == "/api/play/h2h")
        #expect(Endpoints.playChallengeHandle(handle: "Bo", pack: "flags").method == .post)
        #expect(Endpoints.playAccept(matchID: "m1").path == "/api/play/h2h/m1/accept")
        #expect(Endpoints.playDecline(matchID: "m1").path == "/api/play/h2h/m1/decline")
        let board = Endpoints.playLeaderboard(scope: .friends, week: .previous)
        #expect(board.path == "/api/play/leaderboard")
        #expect(board.query == [URLQueryItem(name: "scope", value: "friends"), URLQueryItem(name: "week", value: "previous")])
        #expect(Endpoints.playChallenge().path == "/api/play/challenge")
    }

    @Test func test_aHandleOrIDCannotEscapeItsPathSegment() {
        #expect(Endpoints.socialPublicProfile(handle: "../etc").path == "/api/social/profile/..%2Fetc")
        #expect(Endpoints.socialIdea(id: "a?b#c d").path == "/api/social/ideas/a%3Fb%23c%20d")
        #expect(Endpoints.playSession(id: "x/../y").path == "/api/play/quiz/x%2F..%2Fy")
    }

    @Test func test_telemetryNamesCarryNoHandleOrID() {
        let names = [
            Endpoints.socialPublicProfile(handle: "secret_handle").telemetryName,
            Endpoints.socialFollow(handle: "secret_handle").telemetryName,
            Endpoints.socialIdea(id: "idea99").telemetryName,
            Endpoints.socialHelpful(commentID: "c99", on: true).telemetryName,
            Endpoints.playSession(id: "sess99").telemetryName,
            Endpoints.playAnswer(sessionID: "sess99", index: 0, choice: "a").telemetryName,
            Endpoints.playAccept(matchID: "m99").telemetryName,
        ]
        for name in names {
            #expect(name.hasPrefix("/api/") && !name.contains("secret") && !name.contains("99"))
        }
    }

    @Test func test_answerIsSentImmediatelyWithOnlyIndexAndChoice() async throws {
        let h = try Harness { _ in
            .init(json: #"{"correct": true, "correct_choice": "b", "points": 140, "elapsed_ms": 1800, "done": false}"#)
        }
        let repo = LivePlayRepository(api: h.api, locale: h.locale)
        let result = try await repo.answer(sessionID: "s1", index: 3, choice: "b")
        #expect(result.correct && result.points == 140 && result.correctChoice == "b")
        let body = try h.body()
        #expect(body.object?.count == 2 && body["index"].int == 3 && body["choice"].string == "b")
        #expect(h.request?.httpMethod == "POST" && h.request?.url?.path == "/api/play/quiz/s1/answer")
    }

    @Test func test_quizStartCarriesTheAppLanguage() async throws {
        let h = try Harness(language: .de) { _ in .init(json: #"{"session_id": "s1", "mode": "daily", "questions": []}"#) }
        let repo = LivePlayRepository(api: h.api, locale: h.locale)
        _ = try await repo.startQuiz(QuizStart(mode: .daily))
        #expect(try h.body()["locale"].string == "de" && h.request?.url?.path == "/api/play/quiz")
    }

    @Test func test_followAnswersAState() async throws {
        let h = try Harness { _ in .init(json: #"{"state": "pending"}"#) }
        let repo = LiveSocialRepository(api: h.api, locale: h.locale)
        #expect(try await repo.follow(handle: "Maria_K") == .pending)
        #expect(h.request?.httpMethod == "PUT" && h.request?.url?.path == "/api/social/follow/maria_k")
    }

    @Test func test_publishSendsTheDraftAndDecodesTheIdea() async throws {
        let h = try Harness {
            _ in .init(json: #"{"id": "i9", "kind": "plan", "title": "T", "caption": "C", "author": {"handle": "me"}, "status": "held", "mine": true}"#)
        }
        let repo = LiveSocialRepository(api: h.api, locale: h.locale)
        let idea = try await repo.publish(IdeaDraft(planID: 4, title: "T", caption: "C"))
        #expect(idea.id == "i9" && idea.status == .held && idea.mine)
        let body = try h.body()
        #expect(body["plan_id"].int == 4 && body["kind"].string == "plan" && body["title"].string == "T")
    }

    @Test func test_deletesAre204AndSaveAnswersAPlan() async throws {
        let h = try Harness { request in
            request.httpMethod == "POST" ? .init(json: #"{"plan_id": 77}"#) : .init(status: 204)
        }
        let repo = LiveSocialRepository(api: h.api, locale: h.locale)
        try await repo.unlike(ideaID: "i1")
        try await repo.unfollow(handle: "a")
        try await repo.report(ReportRequest(target: .comment, id: "c1", reason: .other))
        #expect(try await repo.save(ideaID: "i1") == 77)
    }

    @Test func test_historyAndMatchesUnwrap() async throws {
        let h = try Harness { request in
            request.url?.path == "/api/play/h2h"
                ? .init(json: #"{"matches": [{"id": "m1", "opponent": {"handle": "a"}, "state": "waiting_you"}]}"#)
                : .init(json: #"{"history": [{"session_id": "s1", "mode": "daily", "score": 5, "correct": 1}]}"#)
        }
        let repo = LivePlayRepository(api: h.api, locale: h.locale)
        #expect(try await repo.matches().map(\.id) == ["m1"])
        #expect(try await repo.history(limit: 5).map(\.sessionID) == ["s1"])
    }

    // MARK: Typed errors

    private func client(_ status: Int, _ code: String, extra: [String: JSONValue] = [:]) -> APIError {
        var body: [String: JSONValue] = ["error_code": .string(code), "detail": .string("x")]
        body.merge(extra) { $1 }
        return .client(status: status, detail: "x", code: nil, body: .object(body))
    }

    @Test func test_socialCodesRead409And422FromTheEnvelope() {
        let cases: [(Int, String, SocialFailure)] = [
            (409, "handle_taken", .handleTaken), (422, "handle_invalid", .handleInvalid), (422, "handle_reserved", .handleReserved),
            (422, "handle_rate_limited", .handleRateLimited), (422, "country_invalid", .countryInvalid),
            (422, "content_rejected", .contentRejected), (422, "limit_reached", .limitReached),
            (422, "cannot_follow_self", .cannotFollowSelf), (422, "cannot_block_self", .cannotBlockSelf),
            (422, "invalid_cursor", .invalidCursor), (422, "title_invalid", .titleInvalid), (422, "text_invalid", .textInvalid),
            (422, "snapshot_too_large", .snapshotTooLarge),
        ]
        for (status, code, expected) in cases { #expect(SocialFailure.from(client(status, code)) == expected) }
        #expect(SocialFailure.from(client(422, "something_new")) == nil)
        #expect(SocialFailure.from(.rateLimited(message: "slow", retryAfter: 3)) == nil)
        #expect(SocialFailure.from(.network) == nil)
    }

    @Test func test_handleRateLimitedCarriesRetryAfterSeconds() {
        let error = client(422, "handle_rate_limited", extra: ["retry_after": .number(86400)])
        #expect(SocialFailure.from(error) == .handleRateLimited && SocialFailure.retryAfter(error) == 86400)
        #expect(SocialFailure.retryAfter(client(422, "handle_taken")) == nil)
        #expect(SocialFailure.retryAfter(.notFound("x")) == nil)
    }

    @Test func test_social403And404AreReadFromTheFixedTexts() {
        #expect(SocialFailure.from(.forbidden("Create a profile first.")) == .profileRequired)
        #expect(SocialFailure.from(.forbidden("Make your profile visible first.")) == .profileRequired)
        #expect(SocialFailure.from(.forbidden("Confirm your email first.")) == .emailUnverified)
        #expect(SocialFailure.from(.forbidden("Your account is restricted for now.")) == .restricted)
        #expect(SocialFailure.from(.forbidden("This idea was taken down.")) == .ideaUnavailable)
        #expect(SocialFailure.from(.forbidden(nil)) == nil)
        #expect(SocialFailure.from(.notFound("Profile not found.")) == .profileNotFound)
        #expect(SocialFailure.from(.notFound("Idea not found.")) == .ideaNotFound)
        #expect(SocialFailure.from(.notFound("Comment not found.")) == .commentNotFound)
        #expect(SocialFailure.from(.notFound("Plan not found.")) == .planNotFound)
        #expect(SocialFailure.from(.notFound("No such follow request.")) == .requestNotFound)
        #expect(SocialFailure.from(.notFound("Nothing to report.")) == .notFound)
        #expect(SocialFailure.from(.notFound("Not found")) == nil && SocialFailure.from(.notFound("Not Found")) == nil)
    }

    @Test func test_featureOffIsAPlainNotFoundOnly() {
        for plain in [APIError.notFound("Not found"), .notFound("Not Found"), .notFound(nil)] {
            #expect(SocialFailure.isFeatureOff(plain) && PlayFailure.isFeatureOff(plain))
        }
        #expect(!SocialFailure.isFeatureOff(.notFound("Profile not found.")))
        #expect(!SocialFailure.isFeatureOff(.forbidden("Not found")) && !SocialFailure.isFeatureOff(.network))
    }

    @Test func test_playCodes() {
        let cases: [(Int, String, PlayFailure)] = [
            (409, "already_done", .alreadyDone), (410, "session_expired", .sessionExpired), (410, "match_expired", .matchExpired),
            (422, "invalid_pack", .invalidPack), (422, "invalid_mode", .invalidMode), (422, "invalid_index", .invalidIndex),
            (422, "invalid_choice", .invalidChoice), (422, "out_of_order", .outOfOrder),
            (422, "cannot_challenge_self", .cannotChallengeSelf), (422, "limit_reached", .limitReached),
            (409, "invalid_state", .invalidState), (409, "profile_required", .profileRequired),
        ]
        for (status, code, expected) in cases { #expect(PlayFailure.from(client(status, code)) == expected) }
        #expect(PlayFailure.from(.forbidden("Play and points are hidden in your account.")) == .gameHidden)
        #expect(PlayFailure.isGameHidden(.forbidden("Play and points are hidden in your account.")))
        #expect(PlayFailure.from(.forbidden("Your account is restricted for now.")) == .restricted)
        #expect(!PlayFailure.isGameHidden(.forbidden("Your account is restricted for now.")))
        #expect(PlayFailure.from(.notFound("Match not found.")) == .matchNotFound)
        #expect(PlayFailure.from(.notFound("Profile not found.")) == .profileNotFound)
        #expect(PlayFailure.from(.notFound("Quiz session not found.")) == .sessionNotFound)
        #expect(PlayFailure.from(.notFound("Not found")) == nil)
    }
}
