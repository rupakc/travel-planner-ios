import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// Which people list a `ProfileListModel` shows.
enum ProfileListKind: Equatable {
    case followers, following, requests, blocked
}

/// One person in a list: a handle and nothing else (no avatar, no name).
struct ProfilePerson: Identifiable, Equatable {
    let handle: String
    var id: String { handle }
}

/// Followers, following (cursor paged), pending follow requests (accept or decline) and blocked people (unblock). A person
/// whose request or block is already gone (`404`) just leaves the list.
@MainActor @Observable
final class ProfileListModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case unavailable
        case failed(kind: ErrorPresentationKind, detail: String?)
    }

    let kind: ProfileListKind
    private(set) var phase: Phase = .loading
    private(set) var people: [ProfilePerson] = []
    private(set) var next: String?
    private(set) var loadingMore = false
    /// Handles whose accept, decline or unblock is in flight.
    private(set) var busy: Set<String> = []
    private(set) var errorText: String?

    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void

    init(env: AppEnvironment, kind: ProfileListKind, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.kind = kind
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    var title: String {
        switch kind {
        case .followers: L10n.text(K.social.profile.followers)
        case .following: L10n.text(K.social.profile.followingLabel)
        case .requests: L10n.text(K.social.editor.requests)
        case .blocked: L10n.text(K.social.editor.blocked)
        }
    }

    var emptyText: String {
        switch kind {
        case .followers: L10n.text(K.social.lists.noFollowers)
        case .following: L10n.text(K.social.lists.noFollowing)
        case .requests: L10n.text(K.social.lists.noRequests)
        case .blocked: L10n.text(K.social.lists.noBlocked)
        }
    }

    var canLoadMore: Bool { next != nil }

    func load() async {
        guard env.social.isAvailable else {
            phase = .unavailable
            return
        }
        if phase != .loaded { phase = .loading }
        do {
            let (list, cursor) = try await fetch(cursor: nil)
            guard !Task.isCancelled else { return }
            people = list
            next = cursor
            phase = .loaded
        } catch is CancellationError {
            return
        } catch is SocialService.Unavailable {
            phase = .unavailable
        } catch let error as APIError {
            if case .cancelled = error { return }
            phase = SocialFailure.isFeatureOff(error) ? .unavailable : .failed(kind: error.presentationKind, detail: error.userFacingDetail)
        } catch {
            phase = .failed(kind: .other, detail: nil)
        }
    }

    func loadMore() async {
        guard let cursor = next, !loadingMore, phase == .loaded else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let (list, following) = try await fetch(cursor: cursor)
            let known = Set(people.map(\.handle))
            people += list.filter { !known.contains($0.handle) }
            next = following
        } catch {
            errorText = SocialMessage.text(for: error)
        }
    }

    private func fetch(cursor: String?) async throws -> ([ProfilePerson], String?) {
        switch kind {
        case .followers:
            let page = try await env.social.call { try await $0.followers(cursor: cursor) }
            return (page.users.map { ProfilePerson(handle: $0.handle) }, page.next)
        case .following:
            let page = try await env.social.call { try await $0.following(cursor: cursor) }
            return (page.users.map { ProfilePerson(handle: $0.handle) }, page.next)
        case .requests:
            let list = try await env.social.call { try await $0.followRequests() }
            return (list.map { ProfilePerson(handle: $0.handle) }, nil)
        case .blocked:
            let list = try await env.social.call { try await $0.blocks() }
            return (list.map { ProfilePerson(handle: $0.handle) }, nil)
        }
    }

    func open(_ person: ProfilePerson) {
        env.router.open(.profile(handle: person.handle))
    }

    func accept(_ person: ProfilePerson) async {
        await act(on: person) { try await $0.acceptRequest(handle: person.handle) }
    }

    func decline(_ person: ProfilePerson) async {
        await act(on: person) { try await $0.declineRequest(handle: person.handle) }
    }

    /// Unblocking makes the pair visible to each other again; it never re-adds a follow.
    func unblock(_ person: ProfilePerson) async {
        let done = await act(on: person) { try await $0.unblock(handle: person.handle) }
        if done { emit(.socialBlock(on: false)) }
    }

    @discardableResult
    private func act(on person: ProfilePerson, _ operation: (any SocialRepository) async throws -> Void) async -> Bool {
        guard !busy.contains(person.handle) else { return false }
        busy.insert(person.handle)
        errorText = nil
        defer { busy.remove(person.handle) }
        do {
            try await env.social.call(operation)
            people.removeAll { $0.handle == person.handle }
            return true
        } catch is CancellationError {
            return false
        } catch {
            if let api = error as? APIError, SocialFailure.from(api) == .requestNotFound {
                people.removeAll { $0.handle == person.handle }
                return true
            }
            errorText = SocialMessage.text(for: error)
            return false
        }
    }
}
