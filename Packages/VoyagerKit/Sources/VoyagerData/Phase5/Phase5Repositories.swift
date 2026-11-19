import Foundation
import Networking
import VoyagerModel

// Social and Play (`docs/Social-API.md`) routes. Every route needs sign-in. Handles are lower-cased (the server stores
// them that way) and escaped as one path segment; telemetry names are templates and never carry a handle or an id.

private struct CommentRequestBody: Encodable, Sendable {
    var text: String
}

private struct AnswerRequestBody: Encodable, Sendable {
    var index: Int
    var choice: String
}

private struct H2HRequestBody: Encodable, Sendable {
    var handle: String
    var pack: String
}

extension Endpoints {
    /// A handle as one path segment: lower-case, everything outside the unreserved set escaped.
    static func handleSegment(_ handle: String) -> String {
        pathSegment(handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func page(_ cursor: String?, limit: Int? = nil) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let cursor, !cursor.isEmpty { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        return items
    }

    // MARK: Profile

    public static func socialProfile() -> Endpoint<OwnProfile> {
        Endpoint(path: "/api/social/profile", telemetryName: "/api/social/profile")
    }

    public static func socialSaveProfile(_ patch: ProfilePatch) -> Endpoint<OwnProfile> {
        Endpoint(method: .put, path: "/api/social/profile", telemetryName: "/api/social/profile", body: patch)
    }

    public static func socialHandleCheck(_ handle: String) -> Endpoint<HandleCheck> {
        Endpoint(
            path: "/api/social/handles/check", telemetryName: "/api/social/handles/check",
            query: [URLQueryItem(name: "handle", value: handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())])
    }

    public static func socialPublicProfile(handle: String) -> Endpoint<PublicProfile> {
        Endpoint(path: "/api/social/profile/" + handleSegment(handle), telemetryName: "/api/social/profile/:handle")
    }

    public static func socialProfileIdeas(handle: String, cursor: String?) -> Endpoint<IdeaPage> {
        Endpoint(
            path: "/api/social/profile/" + handleSegment(handle) + "/ideas", telemetryName: "/api/social/profile/:handle/ideas",
            query: page(cursor))
    }

    // MARK: Follow and block

    public static func socialFollow(handle: String) -> Endpoint<FollowAnswer> {
        Endpoint(method: .put, path: "/api/social/follow/" + handleSegment(handle), telemetryName: "/api/social/follow/:handle")
    }

    public static func socialUnfollow(handle: String) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/social/follow/" + handleSegment(handle), telemetryName: "/api/social/follow/:handle")
    }

    public static func socialFollowRequests() -> Endpoint<FollowRequestList> {
        Endpoint(path: "/api/social/follow-requests", telemetryName: "/api/social/follow-requests")
    }

    public static func socialAcceptRequest(handle: String) -> Endpoint<Empty> {
        Endpoint(
            method: .post, path: "/api/social/follow-requests/" + handleSegment(handle) + "/accept",
            telemetryName: "/api/social/follow-requests/:handle/accept")
    }

    public static func socialDeclineRequest(handle: String) -> Endpoint<Empty> {
        Endpoint(
            method: .post, path: "/api/social/follow-requests/" + handleSegment(handle) + "/decline",
            telemetryName: "/api/social/follow-requests/:handle/decline")
    }

    public static func socialFollowers(cursor: String?) -> Endpoint<UserPage> {
        Endpoint(path: "/api/social/followers", telemetryName: "/api/social/followers", query: page(cursor))
    }

    public static func socialFollowing(cursor: String?) -> Endpoint<UserPage> {
        Endpoint(path: "/api/social/following", telemetryName: "/api/social/following", query: page(cursor))
    }

    public static func socialBlock(handle: String) -> Endpoint<Empty> {
        Endpoint(method: .put, path: "/api/social/block/" + handleSegment(handle), telemetryName: "/api/social/block/:handle")
    }

    public static func socialUnblock(handle: String) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/social/block/" + handleSegment(handle), telemetryName: "/api/social/block/:handle")
    }

    public static func socialBlocks() -> Endpoint<UserPage> {
        Endpoint(path: "/api/social/blocks", telemetryName: "/api/social/blocks")
    }

    // MARK: Ideas

    public static func socialFeed(scope: FeedScope, cursor: String?, limit: Int?) -> Endpoint<IdeaPage> {
        var query = [URLQueryItem(name: "scope", value: scope.rawValue)]
        query += page(cursor, limit: limit.map { min(max($0, 1), 30) })
        return Endpoint(path: "/api/social/feed", telemetryName: "/api/social/feed", query: query)
    }

    public static func socialIdea(id: String) -> Endpoint<Idea> {
        Endpoint(path: "/api/social/ideas/" + pathSegment(id), telemetryName: "/api/social/ideas/:id")
    }

    public static func socialPublish(_ draft: IdeaDraft) -> Endpoint<Idea> {
        Endpoint(method: .post, path: "/api/social/ideas", telemetryName: "/api/social/ideas", body: draft)
    }

    public static func socialDeleteIdea(id: String) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/social/ideas/" + pathSegment(id), telemetryName: "/api/social/ideas/:id")
    }

    public static func socialLike(ideaID: String, on: Bool) -> Endpoint<Empty> {
        Endpoint(
            method: on ? .put : .delete, path: "/api/social/ideas/" + pathSegment(ideaID) + "/like",
            telemetryName: "/api/social/ideas/:id/like")
    }

    public static func socialSave(ideaID: String) -> Endpoint<SavedIdea> {
        Endpoint(method: .post, path: "/api/social/ideas/" + pathSegment(ideaID) + "/save", telemetryName: "/api/social/ideas/:id/save")
    }

    public static func socialForgetSave(ideaID: String) -> Endpoint<Empty> {
        Endpoint(
            method: .delete, path: "/api/social/ideas/" + pathSegment(ideaID) + "/save", telemetryName: "/api/social/ideas/:id/save")
    }

    // MARK: Comments and reports

    public static func socialComments(ideaID: String, cursor: String?) -> Endpoint<CommentPage> {
        Endpoint(
            path: "/api/social/ideas/" + pathSegment(ideaID) + "/comments", telemetryName: "/api/social/ideas/:id/comments",
            query: page(cursor))
    }

    public static func socialComment(ideaID: String, text: String) -> Endpoint<IdeaComment> {
        Endpoint(
            method: .post, path: "/api/social/ideas/" + pathSegment(ideaID) + "/comments",
            telemetryName: "/api/social/ideas/:id/comments", body: CommentRequestBody(text: text))
    }

    public static func socialDeleteComment(id: String) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/social/comments/" + pathSegment(id), telemetryName: "/api/social/comments/:id")
    }

    public static func socialHelpful(commentID: String, on: Bool) -> Endpoint<Empty> {
        Endpoint(
            method: on ? .put : .delete, path: "/api/social/comments/" + pathSegment(commentID) + "/helpful",
            telemetryName: "/api/social/comments/:id/helpful")
    }

    public static func socialReport(_ request: ReportRequest) -> Endpoint<Empty> {
        Endpoint(method: .post, path: "/api/social/reports", telemetryName: "/api/social/reports", body: request)
    }

    // MARK: Play

    public static func playState() -> Endpoint<PlayState> {
        Endpoint(path: "/api/play/state", telemetryName: "/api/play/state")
    }

    public static func playStartQuiz(_ start: QuizStart) -> Endpoint<QuizSession> {
        Endpoint(method: .post, path: "/api/play/quiz", telemetryName: "/api/play/quiz", body: start)
    }

    public static func playSession(id: String) -> Endpoint<QuizSession> {
        Endpoint(path: "/api/play/quiz/" + pathSegment(id), telemetryName: "/api/play/quiz/:id")
    }

    public static func playAnswer(sessionID: String, index: Int, choice: String) -> Endpoint<AnswerResult> {
        Endpoint(
            method: .post, path: "/api/play/quiz/" + pathSegment(sessionID) + "/answer", telemetryName: "/api/play/quiz/:id/answer",
            body: AnswerRequestBody(index: index, choice: choice))
    }

    public static func playHistory(limit: Int?) -> Endpoint<QuizHistory> {
        Endpoint(
            path: "/api/play/history", telemetryName: "/api/play/history",
            query: limit.map { [URLQueryItem(name: "limit", value: String(max($0, 1)))] } ?? [])
    }

    public static func playMatches() -> Endpoint<H2HList> {
        Endpoint(path: "/api/play/h2h", telemetryName: "/api/play/h2h")
    }

    public static func playChallengeHandle(handle: String, pack: String) -> Endpoint<QuizSession> {
        Endpoint(
            method: .post, path: "/api/play/h2h", telemetryName: "/api/play/h2h",
            body: H2HRequestBody(handle: handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), pack: pack))
    }

    public static func playAccept(matchID: String) -> Endpoint<QuizSession> {
        Endpoint(
            method: .post, path: "/api/play/h2h/" + pathSegment(matchID) + "/accept", telemetryName: "/api/play/h2h/:id/accept")
    }

    public static func playDecline(matchID: String) -> Endpoint<Empty> {
        Endpoint(
            method: .post, path: "/api/play/h2h/" + pathSegment(matchID) + "/decline", telemetryName: "/api/play/h2h/:id/decline")
    }

    public static func playLeaderboard(scope: BoardScope, week: BoardWeek) -> Endpoint<Leaderboard> {
        Endpoint(
            path: "/api/play/leaderboard", telemetryName: "/api/play/leaderboard",
            query: [URLQueryItem(name: "scope", value: scope.rawValue), URLQueryItem(name: "week", value: week.rawValue)])
    }

    public static func playChallenge() -> Endpoint<PlayChallenge> {
        Endpoint(path: "/api/play/challenge", telemetryName: "/api/play/challenge")
    }
}

public struct LiveSocialRepository: SocialRepository {
    private let api: APIClient

    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.api = api
    }

    public func profile() async throws -> OwnProfile { try await api.send(Endpoints.socialProfile()) }
    public func saveProfile(_ patch: ProfilePatch) async throws -> OwnProfile { try await api.send(Endpoints.socialSaveProfile(patch)) }
    public func checkHandle(_ handle: String) async throws -> HandleCheck { try await api.send(Endpoints.socialHandleCheck(handle)) }
    public func publicProfile(handle: String) async throws -> PublicProfile {
        try await api.send(Endpoints.socialPublicProfile(handle: handle))
    }
    public func ideas(of handle: String, cursor: String?) async throws -> IdeaPage {
        try await api.send(Endpoints.socialProfileIdeas(handle: handle, cursor: cursor))
    }

    public func follow(handle: String) async throws -> FollowState {
        try await api.send(Endpoints.socialFollow(handle: handle)).state
    }
    public func unfollow(handle: String) async throws { _ = try await api.send(Endpoints.socialUnfollow(handle: handle)) }
    public func followRequests() async throws -> [FollowRequest] { try await api.send(Endpoints.socialFollowRequests()).requests }
    public func acceptRequest(handle: String) async throws { _ = try await api.send(Endpoints.socialAcceptRequest(handle: handle)) }
    public func declineRequest(handle: String) async throws { _ = try await api.send(Endpoints.socialDeclineRequest(handle: handle)) }
    public func followers(cursor: String?) async throws -> UserPage { try await api.send(Endpoints.socialFollowers(cursor: cursor)) }
    public func following(cursor: String?) async throws -> UserPage { try await api.send(Endpoints.socialFollowing(cursor: cursor)) }
    public func block(handle: String) async throws { _ = try await api.send(Endpoints.socialBlock(handle: handle)) }
    public func unblock(handle: String) async throws { _ = try await api.send(Endpoints.socialUnblock(handle: handle)) }
    public func blocks() async throws -> [HandleUser] { try await api.send(Endpoints.socialBlocks()).users }

    public func feed(scope: FeedScope, cursor: String?, limit: Int?) async throws -> IdeaPage {
        try await api.send(Endpoints.socialFeed(scope: scope, cursor: cursor, limit: limit))
    }
    public func idea(id: String) async throws -> Idea { try await api.send(Endpoints.socialIdea(id: id)) }
    public func publish(_ draft: IdeaDraft) async throws -> Idea { try await api.send(Endpoints.socialPublish(draft)) }
    public func deleteIdea(id: String) async throws { _ = try await api.send(Endpoints.socialDeleteIdea(id: id)) }
    public func like(ideaID: String) async throws { _ = try await api.send(Endpoints.socialLike(ideaID: ideaID, on: true)) }
    public func unlike(ideaID: String) async throws { _ = try await api.send(Endpoints.socialLike(ideaID: ideaID, on: false)) }
    public func save(ideaID: String) async throws -> Int { try await api.send(Endpoints.socialSave(ideaID: ideaID)).planID }
    public func forgetSave(ideaID: String) async throws { _ = try await api.send(Endpoints.socialForgetSave(ideaID: ideaID)) }

    public func comments(ideaID: String, cursor: String?) async throws -> CommentPage {
        try await api.send(Endpoints.socialComments(ideaID: ideaID, cursor: cursor))
    }
    public func comment(ideaID: String, text: String) async throws -> IdeaComment {
        try await api.send(Endpoints.socialComment(ideaID: ideaID, text: text))
    }
    public func deleteComment(id: String) async throws { _ = try await api.send(Endpoints.socialDeleteComment(id: id)) }
    public func markHelpful(commentID: String) async throws {
        _ = try await api.send(Endpoints.socialHelpful(commentID: commentID, on: true))
    }
    public func unmarkHelpful(commentID: String) async throws {
        _ = try await api.send(Endpoints.socialHelpful(commentID: commentID, on: false))
    }

    public func report(_ request: ReportRequest) async throws { _ = try await api.send(Endpoints.socialReport(request)) }
}

public struct LivePlayRepository: PlayRepository {
    private let api: APIClient
    private let locale: @Sendable () -> AppLanguage

    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.api = api
        self.locale = locale
    }

    public func state() async throws -> PlayState { try await api.send(Endpoints.playState()) }

    /// The quiz language is the app's language unless the start names one.
    public func startQuiz(_ start: QuizStart) async throws -> QuizSession {
        var start = start
        if start.locale == nil { start.locale = locale().rawValue }
        return try await api.send(Endpoints.playStartQuiz(start))
    }

    public func session(id: String) async throws -> QuizSession { try await api.send(Endpoints.playSession(id: id)) }
    public func answer(sessionID: String, index: Int, choice: String) async throws -> AnswerResult {
        try await api.send(Endpoints.playAnswer(sessionID: sessionID, index: index, choice: choice))
    }
    public func history(limit: Int?) async throws -> [QuizHistoryEntry] { try await api.send(Endpoints.playHistory(limit: limit)).entries }

    public func matches() async throws -> [H2HMatch] { try await api.send(Endpoints.playMatches()).matches }
    public func challenge(handle: String, pack: String) async throws -> QuizSession {
        try await api.send(Endpoints.playChallengeHandle(handle: handle, pack: pack))
    }
    public func accept(matchID: String) async throws -> QuizSession { try await api.send(Endpoints.playAccept(matchID: matchID)) }
    public func decline(matchID: String) async throws { _ = try await api.send(Endpoints.playDecline(matchID: matchID)) }

    public func leaderboard(scope: BoardScope, week: BoardWeek) async throws -> Leaderboard {
        try await api.send(Endpoints.playLeaderboard(scope: scope, week: week))
    }
    public func challengeOfTheWeek() async throws -> PlayChallenge { try await api.send(Endpoints.playChallenge()) }
}

// MARK: Typed errors

/// The error codes of `Social-API.md` (`/social/*`) that clients translate. Everything else keeps the backend `detail`.
///
/// `ErrorMapping` keeps only the `detail` of a 403 or 404 (the envelope's `error_code` is dropped), so those two are
/// read from the backend's fixed texts (`Not found` for a disabled feature, `Profile not found.`, `Idea not found.`,
/// `Confirm your email first.`, ...). A bare FastAPI `Not Found` is a missing route. 409, 410 and 422 keep their code.
public enum SocialFailure: String, Error, Sendable, Hashable, CaseIterable {
    case socialDisabled = "social_disabled"
    case handleTaken = "handle_taken"
    case handleInvalid = "handle_invalid"
    case handleReserved = "handle_reserved"
    case handleRateLimited = "handle_rate_limited"
    case countryInvalid = "country_invalid"
    case contentRejected = "content_rejected"
    case profileRequired = "profile_required"
    case emailUnverified = "email_unverified"
    case restricted
    case profileNotFound = "profile_not_found"
    case requestNotFound = "request_not_found"
    case ideaNotFound = "idea_not_found"
    case commentNotFound = "comment_not_found"
    case planNotFound = "plan_not_found"
    case notFound = "not_found"
    case ideaUnavailable = "idea_unavailable"
    case cannotFollowSelf = "cannot_follow_self"
    case cannotBlockSelf = "cannot_block_self"
    case invalidCursor = "invalid_cursor"
    case limitReached = "limit_reached"
    case titleInvalid = "title_invalid"
    case textInvalid = "text_invalid"
    case snapshotTooLarge = "snapshot_too_large"

    public static func from(_ error: APIError) -> SocialFailure? {
        switch error {
        case .client(_, _, let code, let body):
            let raw = body["error_code"].string ?? code ?? body["detail"]["error_code"].string
            return raw.flatMap(SocialFailure.init(rawValue:))
        case .forbidden(let detail):
            return fromForbidden(detail: detail)
        case .notFound(let detail):
            return fromNotFound(detail: detail)
        default:
            return nil
        }
    }

    /// Seconds to wait after `handle_rate_limited` (the envelope's extra `retry_after`).
    public static func retryAfter(_ error: APIError) -> Int? {
        guard case .client(_, _, _, let body) = error else { return nil }
        let value = body["retry_after"].int ?? body["detail"]["retry_after"].int
        return value.flatMap { $0 >= 0 ? $0 : nil }
    }

    /// The route is missing, or the feature is switched off (`404 social_disabled` says `Not found`): `/config` was stale.
    public static func isFeatureOff(_ error: APIError) -> Bool {
        guard case .notFound(let detail) = error else { return false }
        return detail == nil || detail?.lowercased() == "not found"
    }

    private static func fromForbidden(detail: String?) -> SocialFailure? {
        guard let text = detail?.lowercased() else { return nil }
        if text.contains("email") { return .emailUnverified }
        if text.contains("restricted") { return .restricted }
        if text.contains("taken down") { return .ideaUnavailable }
        if text.contains("profile") { return .profileRequired }
        return nil
    }

    private static func fromNotFound(detail: String?) -> SocialFailure? {
        guard let text = detail?.lowercased(), text != "not found" else { return nil }
        if text.contains("follow request") { return .requestNotFound }
        if text.contains("profile") { return .profileNotFound }
        if text.contains("idea") { return .ideaNotFound }
        if text.contains("comment") { return .commentNotFound }
        if text.contains("plan") { return .planNotFound }
        if text.contains("nothing to report") { return .notFound }
        return nil
    }
}

/// The error codes of `Social-API.md` (`/play/*`) that clients translate; same reading rules as `SocialFailure`.
public enum PlayFailure: String, Error, Sendable, Hashable, CaseIterable {
    case playDisabled = "play_disabled"
    case gameHidden = "game_hidden"
    case alreadyDone = "already_done"
    case sessionExpired = "session_expired"
    case matchExpired = "match_expired"
    case invalidPack = "invalid_pack"
    case invalidMode = "invalid_mode"
    case invalidIndex = "invalid_index"
    case invalidChoice = "invalid_choice"
    case outOfOrder = "out_of_order"
    case sessionNotFound = "session_not_found"
    case matchNotFound = "match_not_found"
    case profileNotFound = "profile_not_found"
    case profileRequired = "profile_required"
    case restricted
    case cannotChallengeSelf = "cannot_challenge_self"
    case limitReached = "limit_reached"
    case invalidState = "invalid_state"

    public static func from(_ error: APIError) -> PlayFailure? {
        switch error {
        case .client(_, _, let code, let body):
            let raw = body["error_code"].string ?? code ?? body["detail"]["error_code"].string
            return raw.flatMap(PlayFailure.init(rawValue:))
        case .forbidden(let detail):
            guard let text = detail?.lowercased() else { return nil }
            if text.contains("hidden") { return .gameHidden }
            if text.contains("restricted") { return .restricted }
            return nil
        case .notFound(let detail):
            guard let text = detail?.lowercased(), text != "not found" else { return nil }
            if text.contains("match") { return .matchNotFound }
            if text.contains("profile") { return .profileNotFound }
            // The backend says "Quiz not found." (older copy: "Quiz session not found.").
            if text.contains("session") || text.contains("quiz") { return .sessionNotFound }
            return nil
        default:
            return nil
        }
    }

    /// `403 game_hidden`: the account hides Play. Entry points go away.
    public static func isGameHidden(_ error: APIError) -> Bool { from(error) == .gameHidden }

    /// The route is missing or Play is switched off (`404 play_disabled`).
    public static func isFeatureOff(_ error: APIError) -> Bool { SocialFailure.isFeatureOff(error) }
}
