import Foundation
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The comments of one idea, oldest first (`GET /social/ideas/{id}/comments`). Posting, deleting (own comment, or any
/// comment on your own idea) and marking helpful (idea author only) go through `SocialService`.
@MainActor @Observable
final class CommentsModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(IdeaFailure)
    }

    static let maxLength = 300

    let ideaID: String
    /// The viewer wrote the idea: may mark helpful and delete any comment.
    let ideaMine: Bool
    private(set) var comments: [IdeaComment] = []
    private(set) var next: String?
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false
    private(set) var isPosting = false
    private(set) var failure: IdeaFailure?
    /// The rules card is showing: the first comment of this user waits for "I agree" (plan ruling R13).
    private(set) var needsRules = false
    var draft = "" {
        didSet { if draft.count > Self.maxLength { draft = String(draft.prefix(Self.maxLength)) } }
    }

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let onCount: @MainActor (Int) -> Void
    @ObservationIgnored private var didLoad = false

    init(
        env: AppEnvironment, ideaID: String, ideaMine: Bool, onCount: @escaping @MainActor (Int) -> Void = { _ in },
        track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.ideaID = ideaID
        self.ideaMine = ideaMine
        self.onCount = onCount
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    var visible: [IdeaComment] { comments.filter { $0.status.isPublished || ($0.status == .held && $0.mine) } }
    var isEmpty: Bool { phase == .loaded && visible.isEmpty }
    var canPost: Bool { !isPosting && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func canDelete(_ comment: IdeaComment) -> Bool { comment.mine || ideaMine }
    func canMarkHelpful(_ comment: IdeaComment) -> Bool { ideaMine && !comment.mine }
    func canReport(_ comment: IdeaComment) -> Bool { !comment.mine }

    func start() async {
        guard !didLoad else { return }
        didLoad = true
        await load()
    }

    func load() async {
        phase = .loading
        do {
            let page = try await env.social.call { [ideaID] in try await $0.comments(ideaID: ideaID, cursor: nil) }
            comments = page.comments
            next = page.next
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(IdeaFailure(error))
        }
    }

    func loadMore() async {
        guard phase == .loaded, let cursor = next, !isLoadingMore else { return }
        isLoadingMore = true
        failure = nil
        defer { isLoadingMore = false }
        do {
            let page = try await env.social.call { [ideaID] in try await $0.comments(ideaID: ideaID, cursor: cursor) }
            let known = Set(comments.map(\.id))
            comments += page.comments.filter { !known.contains($0.id) }
            next = page.next
        } catch is CancellationError {
            return
        } catch {
            failure = IdeaFailure(error)
        }
    }

    private var username: String { env.auth.session?.user.username ?? "" }

    func post() async {
        guard canPost else { return }
        guard env.device.hasAcceptedCommunityRules(for: username) else {
            needsRules = true
            return
        }
        await send()
    }

    func acceptRules() async {
        env.device.acceptCommunityRules(for: username)
        needsRules = false
        await send()
    }

    func declineRules() { needsRules = false }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canPost else { return }
        isPosting = true
        failure = nil
        defer { isPosting = false }
        do {
            let comment = try await env.social.call { [ideaID] in try await $0.comment(ideaID: ideaID, text: text) }
            comments.append(comment)
            draft = ""
            emit(.socialComment)
            onCount(1)
        } catch is CancellationError {
            return
        } catch {
            failure = IdeaFailure(error)
        }
    }

    func delete(_ comment: IdeaComment) async {
        guard canDelete(comment) else { return }
        failure = nil
        do {
            try await env.social.call { try await $0.deleteComment(id: comment.id) }
            comments.removeAll { $0.id == comment.id }
            onCount(-1)
        } catch is CancellationError {
            return
        } catch {
            let failed = IdeaFailure(error)
            if failed.isGone {
                comments.removeAll { $0.id == comment.id }
            } else {
                failure = failed
            }
        }
    }

    func toggleHelpful(_ comment: IdeaComment) async {
        guard canMarkHelpful(comment), let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        failure = nil
        let on = !comment.helpful
        do {
            try await env.social.call { repository in
                if on {
                    try await repository.markHelpful(commentID: comment.id)
                } else {
                    try await repository.unmarkHelpful(commentID: comment.id)
                }
            }
            if comments.indices.contains(index), comments[index].id == comment.id { comments[index].helpful = on }
        } catch is CancellationError {
            return
        } catch {
            failure = IdeaFailure(error)
        }
    }
}
