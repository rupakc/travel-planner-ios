import Foundation
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The Ideas feed (`GET /social/feed`): one scope at a time, cursor paging, like and save on each card. Held ideas show
/// only to their author (as a notice, never the text to others); hidden and removed ones never show.
@MainActor @Observable
final class FeedModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(IdeaFailure)
        /// `features.social` is off (or the route turned out to be missing): the screen is not offered.
        case unavailable
    }

    private(set) var scope: FeedScope = .forYou
    private(set) var ideas: [Idea] = []
    private(set) var next: String?
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false
    /// A "show more" that failed (the list stays, the button retries).
    private(set) var loadMoreFailure: IdeaFailure?
    /// A like, save or delete that failed, for the card's own line.
    private(set) var actionFailure: [String: IdeaFailure] = [:]
    /// The plan a save made, per idea, until the card has been told ("Saved to your plans").
    private(set) var savedNote: Set<String> = []
    /// The caller has no profile yet (the prompt shows); nil while unknown.
    private(set) var hasProfile: Bool?

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let actions: IdeaActions
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var didStart = false

    init(env: AppEnvironment, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        let telemetry = env.telemetry
        let emit = track ?? { telemetry.track($0) }
        self.emit = emit
        self.actions = IdeaActions(env: env, track: emit)
    }

    var isAvailable: Bool { env.social.isAvailable }

    /// What the list shows: published ideas, plus the caller's own held ones (with their notice).
    var visible: [Idea] { ideas.filter { $0.status.isPublished || ($0.status == .held && $0.mine) } }

    var isEmpty: Bool { phase == .loaded && visible.isEmpty }

    var hasMore: Bool { next != nil }

    var showsProfilePrompt: Bool { hasProfile == false }

    // MARK: Loading

    /// First load of the screen (once); later calls do nothing.
    func start() async {
        guard !didStart else { return }
        didStart = true
        async let profile: Void = loadProfile()
        await load()
        await profile
    }

    func select(_ new: FeedScope) async {
        guard new != scope else { return }
        scope = new
        await load()
    }

    /// Reloads the current scope from the top (pull to refresh, retry).
    func load() async {
        guard isAvailable else {
            phase = .unavailable
            return
        }
        generation += 1
        let mine = generation
        let scope = scope
        if ideas.isEmpty || phase != .loaded { phase = .loading }
        do {
            let page = try await env.social.call { try await $0.feed(scope: scope, cursor: nil, limit: Self.pageSize) }
            guard mine == generation else { return }
            ideas = Self.unique(page.ideas)
            next = page.next
            loadMoreFailure = nil
            phase = .loaded
            emit(.socialFeedView(scope: scope.rawValue))
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            let failure = IdeaFailure(error)
            phase = failure.unavailable ? .unavailable : .failed(failure)
            if case .failed = phase {
                ideas = []
                next = nil
            }
        }
    }

    func loadMore() async {
        guard phase == .loaded, let cursor = next, !isLoadingMore else { return }
        let mine = generation
        let scope = scope
        isLoadingMore = true
        loadMoreFailure = nil
        defer { isLoadingMore = false }
        do {
            let page = try await env.social.call { try await $0.feed(scope: scope, cursor: cursor, limit: Self.pageSize) }
            guard mine == generation else { return }
            ideas = Self.unique(ideas + page.ideas)
            next = page.next
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            loadMoreFailure = IdeaFailure(error)
        }
    }

    private func loadProfile() async {
        guard isAvailable else { return }
        if let profile = try? await env.social.call({ try await $0.profile() }) {
            hasProfile = profile.handle != nil
        }
    }

    // MARK: Card actions

    func opened(_ idea: Idea) {
        emit(.socialIdeaOpen)
        env.router.open(.ideaDetail(id: idea.id))
    }

    /// Optimistic like; a second tap while the first is in flight is ignored, a failure puts the card back.
    func toggleLike(_ id: String) async {
        guard let index = ideas.firstIndex(where: { $0.id == id }), !inFlight.contains(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        let before = ideas[index]
        let on = !before.liked
        actionFailure[id] = nil
        ideas[index] = before.settingLike(on)
        do {
            try await actions.setLike(id, on: on)
        } catch is CancellationError {
            replace(before)
        } catch {
            replace(before)
            actionFailure[id] = IdeaFailure(error)
        }
    }

    /// Remixes the idea into a new plan and opens it. Saving again opens the existing copy.
    func save(_ id: String) async {
        guard let before = ideas.first(where: { $0.id == id }), !inFlight.contains(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        actionFailure[id] = nil
        do {
            let planID = try await actions.save(id)
            replace(before.markingSaved())
            savedNote.insert(id)
            env.router.open(.planDetail(id: planID))
        } catch is CancellationError {
            return
        } catch {
            actionFailure[id] = IdeaFailure(error)
        }
    }

    func delete(_ id: String) async {
        guard ideas.contains(where: { $0.id == id && $0.mine }), !inFlight.contains(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        actionFailure[id] = nil
        do {
            try await actions.delete(id)
            ideas.removeAll { $0.id == id }
        } catch is CancellationError {
            return
        } catch {
            let failure = IdeaFailure(error)
            // Already gone on the server: the card goes too.
            if failure.isGone { ideas.removeAll { $0.id == id } } else { actionFailure[id] = failure }
        }
    }

    /// A reported idea stays until the server hides it; the sheet says thanks.
    func report(_ request: ReportRequest) async throws {
        try await actions.report(request)
    }

    /// A blocked author's ideas leave the list at once (the server also hides them from the next load).
    func blocked(handle: String) {
        ideas.removeAll { $0.author.handle == handle }
    }

    func clearFailure(_ id: String) {
        actionFailure[id] = nil
    }

    // MARK: Plumbing

    static let pageSize = 20

    private func replace(_ idea: Idea) {
        if let index = ideas.firstIndex(where: { $0.id == idea.id }) { ideas[index] = idea }
    }

    private static func unique(_ ideas: [Idea]) -> [Idea] {
        var seen = Set<String>()
        return ideas.filter { seen.insert($0.id).inserted }
    }
}

extension Idea {
    /// The card with the like set to `on`, its count moved by one (never below zero).
    func settingLike(_ on: Bool) -> Idea {
        guard on != liked else { return self }
        var copy = self
        copy.liked = on
        copy.likes = max(0, likes + (on ? 1 : -1))
        return copy
    }

    /// The card after a save: marked, with the count up by one the first time only.
    func markingSaved() -> Idea {
        var copy = self
        if !saved { copy.saves += 1 }
        copy.saved = true
        return copy
    }
}
