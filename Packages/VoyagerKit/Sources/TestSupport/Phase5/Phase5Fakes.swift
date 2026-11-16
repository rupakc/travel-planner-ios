import Foundation
import VoyagerModel

// Swift's tuple labels carry the argument names of the repository methods.
// swiftlint:disable large_tuple

/// A scripted `SocialRepository`. Reads that have a natural empty answer default to it; everything that creates or
/// changes something is unscripted (throws `notScripted`) unless a test says otherwise. Every call is recorded.
public final class FakeSocialRepository: SocialRepository {
    public let onProfile = FakeCall<Void, OwnProfile>("social.profile") { _ in OwnProfile() }
    public let onSaveProfile = FakeCall<ProfilePatch, OwnProfile>("social.saveProfile")
    public let onCheckHandle = FakeCall<String, HandleCheck>("social.checkHandle") { _ in HandleCheck(available: true) }
    public let onPublicProfile = FakeCall<String, PublicProfile>("social.publicProfile")
    public let onIdeasOf = FakeCall<(handle: String, cursor: String?), IdeaPage>("social.ideasOf") { _ in IdeaPage() }

    public let onFollow = FakeCall<String, FollowState>("social.follow") { _ in .following }
    public let onUnfollow = FakeCall<String, Void>("social.unfollow") { _ in }
    public let onFollowRequests = FakeCall<Void, [FollowRequest]>("social.followRequests") { _ in [] }
    public let onAcceptRequest = FakeCall<String, Void>("social.acceptRequest") { _ in }
    public let onDeclineRequest = FakeCall<String, Void>("social.declineRequest") { _ in }
    public let onFollowers = FakeCall<String?, UserPage>("social.followers") { _ in UserPage() }
    public let onFollowing = FakeCall<String?, UserPage>("social.following") { _ in UserPage() }
    public let onBlock = FakeCall<String, Void>("social.block") { _ in }
    public let onUnblock = FakeCall<String, Void>("social.unblock") { _ in }
    public let onBlocks = FakeCall<Void, [HandleUser]>("social.blocks") { _ in [] }

    public let onFeed = FakeCall<(scope: FeedScope, cursor: String?, limit: Int?), IdeaPage>("social.feed") { _ in IdeaPage() }
    public let onIdea = FakeCall<String, Idea>("social.idea")
    public let onPublish = FakeCall<IdeaDraft, Idea>("social.publish")
    public let onDeleteIdea = FakeCall<String, Void>("social.deleteIdea") { _ in }
    public let onLike = FakeCall<String, Void>("social.like") { _ in }
    public let onUnlike = FakeCall<String, Void>("social.unlike") { _ in }
    public let onSave = FakeCall<String, Int>("social.save")
    public let onForgetSave = FakeCall<String, Void>("social.forgetSave") { _ in }

    public let onComments = FakeCall<(ideaID: String, cursor: String?), CommentPage>("social.comments") { _ in CommentPage() }
    public let onComment = FakeCall<(ideaID: String, text: String), IdeaComment>("social.comment")
    public let onDeleteComment = FakeCall<String, Void>("social.deleteComment") { _ in }
    public let onMarkHelpful = FakeCall<String, Void>("social.markHelpful") { _ in }
    public let onUnmarkHelpful = FakeCall<String, Void>("social.unmarkHelpful") { _ in }

    public let onReport = FakeCall<ReportRequest, Void>("social.report") { _ in }

    public init() {}

    public func profile() async throws -> OwnProfile { try await onProfile() }
    public func saveProfile(_ patch: ProfilePatch) async throws -> OwnProfile { try await onSaveProfile(patch) }
    public func checkHandle(_ handle: String) async throws -> HandleCheck { try await onCheckHandle(handle) }
    public func publicProfile(handle: String) async throws -> PublicProfile { try await onPublicProfile(handle) }
    public func ideas(of handle: String, cursor: String?) async throws -> IdeaPage { try await onIdeasOf((handle, cursor)) }

    public func follow(handle: String) async throws -> FollowState { try await onFollow(handle) }
    public func unfollow(handle: String) async throws { try await onUnfollow(handle) }
    public func followRequests() async throws -> [FollowRequest] { try await onFollowRequests() }
    public func acceptRequest(handle: String) async throws { try await onAcceptRequest(handle) }
    public func declineRequest(handle: String) async throws { try await onDeclineRequest(handle) }
    public func followers(cursor: String?) async throws -> UserPage { try await onFollowers(cursor) }
    public func following(cursor: String?) async throws -> UserPage { try await onFollowing(cursor) }
    public func block(handle: String) async throws { try await onBlock(handle) }
    public func unblock(handle: String) async throws { try await onUnblock(handle) }
    public func blocks() async throws -> [HandleUser] { try await onBlocks() }

    public func feed(scope: FeedScope, cursor: String?, limit: Int?) async throws -> IdeaPage {
        try await onFeed((scope, cursor, limit))
    }
    public func idea(id: String) async throws -> Idea { try await onIdea(id) }
    public func publish(_ draft: IdeaDraft) async throws -> Idea { try await onPublish(draft) }
    public func deleteIdea(id: String) async throws { try await onDeleteIdea(id) }
    public func like(ideaID: String) async throws { try await onLike(ideaID) }
    public func unlike(ideaID: String) async throws { try await onUnlike(ideaID) }
    public func save(ideaID: String) async throws -> Int { try await onSave(ideaID) }
    public func forgetSave(ideaID: String) async throws { try await onForgetSave(ideaID) }

    public func comments(ideaID: String, cursor: String?) async throws -> CommentPage { try await onComments((ideaID, cursor)) }
    public func comment(ideaID: String, text: String) async throws -> IdeaComment { try await onComment((ideaID, text)) }
    public func deleteComment(id: String) async throws { try await onDeleteComment(id) }
    public func markHelpful(commentID: String) async throws { try await onMarkHelpful(commentID) }
    public func unmarkHelpful(commentID: String) async throws { try await onUnmarkHelpful(commentID) }

    public func report(_ request: ReportRequest) async throws { try await onReport(request) }
}

/// A scripted `PlayRepository`. State, history and matches default to empty; sessions and answers are unscripted.
public final class FakePlayRepository: PlayRepository {
    public let onState = FakeCall<Void, PlayState>("play.state") { _ in PlayState() }
    public let onStartQuiz = FakeCall<QuizStart, QuizSession>("play.startQuiz")
    public let onSession = FakeCall<String, QuizSession>("play.session")
    public let onAnswer = FakeCall<(sessionID: String, index: Int, choice: String), AnswerResult>("play.answer")
    public let onHistory = FakeCall<Int?, [QuizHistoryEntry]>("play.history") { _ in [] }

    public let onMatches = FakeCall<Void, [H2HMatch]>("play.matches") { _ in [] }
    public let onChallenge = FakeCall<(handle: String, pack: String), QuizSession>("play.challenge")
    public let onAccept = FakeCall<String, QuizSession>("play.accept")
    public let onDecline = FakeCall<String, Void>("play.decline") { _ in }

    public let onLeaderboard = FakeCall<(scope: BoardScope, week: BoardWeek), Leaderboard>("play.leaderboard") { _ in Leaderboard() }
    public let onChallengeOfTheWeek = FakeCall<Void, PlayChallenge>("play.challengeOfTheWeek")

    public init() {}

    public func state() async throws -> PlayState { try await onState() }
    public func startQuiz(_ start: QuizStart) async throws -> QuizSession { try await onStartQuiz(start) }
    public func session(id: String) async throws -> QuizSession { try await onSession(id) }
    public func answer(sessionID: String, index: Int, choice: String) async throws -> AnswerResult {
        try await onAnswer((sessionID, index, choice))
    }
    public func history(limit: Int?) async throws -> [QuizHistoryEntry] { try await onHistory(limit) }

    public func matches() async throws -> [H2HMatch] { try await onMatches() }
    public func challenge(handle: String, pack: String) async throws -> QuizSession { try await onChallenge((handle, pack)) }
    public func accept(matchID: String) async throws -> QuizSession { try await onAccept(matchID) }
    public func decline(matchID: String) async throws { try await onDecline(matchID) }

    public func leaderboard(scope: BoardScope, week: BoardWeek) async throws -> Leaderboard { try await onLeaderboard((scope, week)) }
    public func challengeOfTheWeek() async throws -> PlayChallenge { try await onChallengeOfTheWeek() }
}

// swiftlint:enable large_tuple
