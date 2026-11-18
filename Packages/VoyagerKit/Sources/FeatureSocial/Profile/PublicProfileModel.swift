import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// Someone's public profile (`GET /social/profile/{handle}`): follow, request, unfollow, block and report. Optional fields
/// show only when the server sent them; level and badges also need the game visible. A private, unknown or blocked
/// profile is the same plain "not available" (a block is silent and two-way, so nothing says which it was).
@MainActor @Observable
final class PublicProfileModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case notFound
        /// `features.social` is off, or the route turned out to be missing.
        case unavailable
        case failed(kind: ErrorPresentationKind, detail: String?)
    }

    enum Relation: Equatable {
        case none, pending, following
    }

    enum Notice: Equatable {
        case failed(String)
        /// Following needs a profile of the caller's own.
        case profileRequired
        case reported
    }

    let handle: String
    private(set) var phase: Phase = .loading
    private(set) var profile: PublicProfile?
    private(set) var relation: Relation = .none
    /// The caller's own profile: shows "Edit profile" instead of Follow.
    private(set) var isMine = false
    private(set) var working = false
    private(set) var notice: Notice?
    private(set) var ideas: [Idea] = []
    private(set) var ideasNext: String?
    private(set) var ideasLoading = false
    /// The block was confirmed; the profile is gone from view.
    private(set) var blocked = false
    var confirmingBlock = false
    var reporting = false

    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let gameVisibility: @MainActor () -> any GameVisibility

    init(
        env: AppEnvironment, handle: String, gameVisibility: (@MainActor () -> any GameVisibility)? = nil,
        track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.handle = HandleRules.normalized(handle)
        self.gameVisibility = gameVisibility ?? { ProfileEditorModel.defaultGameVisibility(env: env) }
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    // MARK: Derived

    var showsLevel: Bool { profile?.level != nil && gameVisibility().showsGame }
    var showsBadges: Bool { !(profile?.badges ?? []).isEmpty && gameVisibility().showsGame }
    var countryName: String? { profile?.homeCountry.map(CountryNames.name) }
    var visitedNames: [String] { (profile?.countries ?? []).map(CountryNames.name) }
    var followsYou: Bool { profile?.you.followsYou == true }
    /// Own ideas that are held for review show to their author; other people's only when published.
    var visibleIdeas: [Idea] {
        let ledger = env.social.ledger
        return ideas.filter { !ledger.deletedIdeaIDs.contains($0.id) && ($0.status.isPublished || $0.mine) }
    }
    var canLoadMoreIdeas: Bool { ideasNext != nil }

    var noticeText: String? {
        switch notice {
        case .failed(let message): message
        case .profileRequired: L10n.text(K.social.errors.profile_required)
        case .reported: L10n.text(K.social.report.sent)
        case nil: nil
        }
    }

    // MARK: Loading

    func load() async {
        guard env.social.isAvailable else {
            phase = .unavailable
            return
        }
        if phase != .loaded { phase = .loading }
        do {
            let loaded = try await env.social.call { [handle] in try await $0.publicProfile(handle: handle) }
            guard !Task.isCancelled else { return }
            profile = loaded
            relation = Self.relation(of: loaded.you)
            phase = .loaded
            emit(.socialProfileView)
            await loadOwner()
            await loadIdeas(reset: true)
        } catch is CancellationError {
            return
        } catch is SocialService.Unavailable {
            phase = .unavailable
        } catch let error as APIError {
            if case .cancelled = error { return }
            if SocialFailure.isFeatureOff(error) {
                phase = .unavailable
            } else if SocialFailure.from(error) == .profileNotFound {
                phase = .notFound
            } else {
                phase = .failed(kind: error.presentationKind, detail: error.userFacingDetail)
            }
        } catch {
            phase = .failed(kind: .other, detail: nil)
        }
    }

    /// Whether this is the caller's own profile (best effort: a failure just means "not known to be mine").
    private func loadOwner() async {
        guard let own = try? await env.social.call({ try await $0.profile() }) else { return }
        isMine = own.handle?.lowercased() == handle
    }

    func loadIdeas(reset: Bool = false) async {
        guard phase == .loaded, !ideasLoading, reset || ideasNext != nil else { return }
        ideasLoading = true
        defer { ideasLoading = false }
        let cursor = reset ? nil : ideasNext
        do {
            let page = try await env.social.call { [handle] in try await $0.ideas(of: handle, cursor: cursor) }
            ideas = reset ? page.ideas : ideas + page.ideas
            ideasNext = page.next
        } catch {
            // The list is a courtesy under the profile: a failure leaves what is there.
            if reset { ideas = [] }
        }
    }

    private static func relation(of you: ProfileRelation) -> Relation {
        if you.following { return .following }
        if you.pending { return .pending }
        return .none
    }

    // MARK: Follow

    /// Follow, request, or (when already following or pending) stop. A follow of a `followers` profile is a request
    /// until its owner accepts; the counts never move on the caller's own say-so.
    func toggleFollow() async {
        guard !working, !isMine, phase == .loaded else { return }
        working = true
        notice = nil
        defer { working = false }
        do {
            switch relation {
            case .none:
                let state = try await env.social.call { [handle] in try await $0.follow(handle: handle) }
                relation = state == .following ? .following : .pending
                emit(.socialFollow(state: state.rawValue))
            case .following, .pending:
                try await env.social.call { [handle] in try await $0.unfollow(handle: handle) }
                relation = .none
                emit(.socialFollow(state: "none"))
            }
        } catch is CancellationError {
            return
        } catch {
            if let api = error as? APIError, SocialFailure.from(api) == .profileRequired {
                notice = .profileRequired
            } else if let api = error as? APIError, SocialFailure.from(api) == .profileNotFound {
                phase = .notFound
            } else {
                notice = .failed(SocialMessage.text(for: error))
            }
        }
    }

    // MARK: Block and report

    func askBlock() {
        confirmingBlock = true
    }

    func confirmBlock() async {
        confirmingBlock = false
        guard !working, !isMine else { return }
        working = true
        defer { working = false }
        do {
            try await env.social.call { [handle] in try await $0.block(handle: handle) }
            env.social.ledger.blocked(handle: handle)
            blocked = true
            profile = nil
            ideas = []
            phase = .notFound
            emit(.socialBlock(on: true))
        } catch is CancellationError {
            return
        } catch {
            notice = .failed(SocialMessage.text(for: error))
        }
    }

    func openEditor() {
        env.router.open(.profileEditor)
    }

    func open(_ idea: Idea) {
        env.router.open(.ideaDetail(id: idea.id))
    }

    func open(handle other: String) {
        env.router.open(.profile(handle: other))
    }

    func reported() {
        notice = .reported
    }

    func dismissNotice() {
        notice = nil
    }
}
