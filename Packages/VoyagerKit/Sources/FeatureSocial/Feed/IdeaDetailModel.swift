import Foundation
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// One idea on its own screen (`GET /social/ideas/{id}`), with its comments below. A blocked, hidden or removed idea is
/// "not available" (the server answers 404 or 403), never an empty card.
@MainActor @Observable
final class IdeaDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case gone
        case failed(IdeaFailure)
    }

    let ideaID: String
    private(set) var idea: Idea?
    private(set) var phase: Phase = .loading
    private(set) var actionFailure: IdeaFailure?
    private(set) var savedNote = false
    private(set) var isDeleted = false
    var commentsOpen = true

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let actions: IdeaActions
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var didStart = false

    init(env: AppEnvironment, ideaID: String, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.ideaID = ideaID
        self.actions = IdeaActions(env: env, track: track)
    }

    /// First load of the screen (once).
    func start() async {
        guard !didStart else { return }
        didStart = true
        await load()
    }

    func load() async {
        phase = .loading
        do {
            let loaded = try await env.social.call { [ideaID] in try await $0.idea(id: ideaID) }
            // Held shows only to its author; anything else not published is gone for the viewer.
            if loaded.status.isPublished || (loaded.status == .held && loaded.mine) {
                idea = loaded
                phase = .loaded
            } else {
                idea = nil
                phase = .gone
            }
        } catch is CancellationError {
            return
        } catch {
            let failure = IdeaFailure(error)
            phase = failure.isGone ? .gone : .failed(failure)
        }
    }

    func toggleLike() async {
        guard let before = idea, !busy else { return }
        busy = true
        defer { busy = false }
        actionFailure = nil
        let on = !before.liked
        idea = before.settingLike(on)
        do {
            try await actions.setLike(before.id, on: on)
        } catch {
            idea = before
            if !(error is CancellationError) { actionFailure = IdeaFailure(error) }
        }
    }

    func save() async {
        guard let before = idea, !busy else { return }
        busy = true
        defer { busy = false }
        actionFailure = nil
        do {
            let planID = try await actions.save(before.id)
            idea = before.markingSaved()
            savedNote = true
            env.router.open(.planDetail(id: planID))
        } catch is CancellationError {
            return
        } catch {
            actionFailure = IdeaFailure(error)
        }
    }

    func delete() async {
        guard let current = idea, current.mine, !busy else { return }
        busy = true
        defer { busy = false }
        actionFailure = nil
        do {
            try await actions.delete(current.id)
            isDeleted = true
            idea = nil
            phase = .gone
        } catch is CancellationError {
            return
        } catch {
            let failure = IdeaFailure(error)
            if failure.isGone {
                isDeleted = true
                idea = nil
                phase = .gone
            } else {
                actionFailure = failure
            }
        }
    }

    func block() async -> Bool {
        guard let current = idea, !current.mine else { return false }
        actionFailure = nil
        do {
            try await actions.block(current.author.handle)
            idea = nil
            phase = .gone
            return true
        } catch {
            if !(error is CancellationError) { actionFailure = IdeaFailure(error) }
            return false
        }
    }

    func commentCountChanged(_ delta: Int) {
        guard var current = idea else { return }
        current.comments = max(0, current.comments + delta)
        idea = current
    }

    func reportModel() -> ReportModel? {
        idea.map { ReportModel(target: .idea, id: $0.id, env: env) }
    }

    func reportModel(commentID: String) -> ReportModel {
        ReportModel(target: .comment, id: commentID, env: env)
    }
}
