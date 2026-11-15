import Foundation

/// The calls of `docs/Social-API.md` under `/social`. Called only when `features.social` is on (`SocialService`).
/// Handles are passed as the user typed or saw them: the repository lower-cases and escapes them.
public protocol SocialRepository: Sendable {
    // Profile
    func profile() async throws -> OwnProfile
    func saveProfile(_ patch: ProfilePatch) async throws -> OwnProfile
    func checkHandle(_ handle: String) async throws -> HandleCheck
    func publicProfile(handle: String) async throws -> PublicProfile
    func ideas(of handle: String, cursor: String?) async throws -> IdeaPage

    // Follow and block
    func follow(handle: String) async throws -> FollowState
    /// Unfollows, or cancels a pending request.
    func unfollow(handle: String) async throws
    func followRequests() async throws -> [FollowRequest]
    func acceptRequest(handle: String) async throws
    func declineRequest(handle: String) async throws
    func followers(cursor: String?) async throws -> UserPage
    func following(cursor: String?) async throws -> UserPage
    func block(handle: String) async throws
    func unblock(handle: String) async throws
    func blocks() async throws -> [HandleUser]

    // Ideas feed
    func feed(scope: FeedScope, cursor: String?, limit: Int?) async throws -> IdeaPage
    func idea(id: String) async throws -> Idea
    func publish(_ draft: IdeaDraft) async throws -> Idea
    func deleteIdea(id: String) async throws
    func like(ideaID: String) async throws
    func unlike(ideaID: String) async throws
    /// Remixes the idea into a new plan of the caller's; returns its id.
    func save(ideaID: String) async throws -> Int
    /// Forgets the save mark; the copied plan stays.
    func forgetSave(ideaID: String) async throws

    // Comments
    func comments(ideaID: String, cursor: String?) async throws -> CommentPage
    func comment(ideaID: String, text: String) async throws -> IdeaComment
    func deleteComment(id: String) async throws
    func markHelpful(commentID: String) async throws
    func unmarkHelpful(commentID: String) async throws

    // Moderation
    func report(_ request: ReportRequest) async throws
}

/// The calls of `docs/Social-API.md` under `/play`. Called only when `features.play` (and the game) is on.
public protocol PlayRepository: Sendable {
    func state() async throws -> PlayState
    func startQuiz(_ start: QuizStart) async throws -> QuizSession
    /// `GET /play/quiz/{id}`: the session with the answers so far (resume).
    func session(id: String) async throws -> QuizSession
    /// Head-to-head sessions use this same route.
    func answer(sessionID: String, index: Int, choice: String) async throws -> AnswerResult
    func history(limit: Int?) async throws -> [QuizHistoryEntry]

    func matches() async throws -> [H2HMatch]
    func challenge(handle: String, pack: String) async throws -> QuizSession
    func accept(matchID: String) async throws -> QuizSession
    func decline(matchID: String) async throws

    func leaderboard(scope: BoardScope, week: BoardWeek) async throws -> Leaderboard
    func challengeOfTheWeek() async throws -> PlayChallenge
}
