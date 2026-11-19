import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// This week's board (global, opt-in; or friends), handles only. The server ranks, scores and decides who appears; the app
/// shows the rows it is given and the caller's own standing.
@MainActor @Observable
final class BoardModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed
    }

    /// What the opt-in card offers under the global board.
    enum OptIn: Equatable {
        case none
        /// A handle exists: one tap sets `leaderboard_opt_in`.
        case join
        /// No profile yet (the server sends no `you`): the profile editor creates one first.
        case needsProfile
    }

    private(set) var phase: Phase = .loading
    private(set) var scope: BoardScope = .friends
    private(set) var week: BoardWeek = .current
    private(set) var board: Leaderboard?
    private(set) var joining = false
    private(set) var errorText: String?
    /// The caller opted in but is unranked on the global board because their profile is private: the server leaves
    /// private profiles off that board, so the card explains it instead of "unranked" forever.
    private(set) var profileIsPrivate = false

    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var generation = 0

    init(env: AppEnvironment, track: @escaping @MainActor (TelemetryEvent) -> Void) {
        self.env = env
        self.emit = track
    }

    var rows: [BoardRow] { board?.rows ?? [] }

    var optIn: OptIn {
        guard scope == .global, board != nil, env.social.isAvailable else { return .none }
        guard let you = board?.you else { return .needsProfile }
        return you.optedIn ? .none : .join
    }

    /// The caller's rank line: only when they are opted in (on the global board) and ranked.
    var mineText: String? {
        guard let you = board?.you, you.optedIn || scope == .friends, let rank = you.rank else { return nil }
        return L10n.text(K.play.board.mine, ["rank": String(rank)], count: you.score)
    }

    /// Opted in to the global board, no rank, and a private profile: the profile has to be visible to be ranked.
    var showsPrivateProfileNote: Bool { scope == .global && profileIsPrivate && board?.you?.rank == nil }

    var showsUnranked: Bool {
        guard !showsPrivateProfileNote else { return false }
        guard let you = board?.you, you.optedIn || scope == .friends else { return false }
        return you.rank == nil
    }

    /// "3. sam (you)": handles only, never a name, e-mail or avatar.
    func line(_ row: BoardRow) -> String {
        var text = "\(row.rank). \(row.handle)"
        if row.isYou { text += " " + L10n.text(K.play.board.you) }
        return text
    }

    func level(_ row: BoardRow) -> String? {
        row.level.map { L10n.text(K.game.chip.level, ["level": String($0)]) }
    }

    func select(scope newScope: BoardScope) async {
        guard newScope != scope else { return }
        scope = newScope
        await load(emitView: true)
    }

    func select(week newWeek: BoardWeek) async {
        guard newWeek != week else { return }
        week = newWeek
        await load(emitView: false)
    }

    func load(emitView: Bool = true) async {
        guard env.play.isAvailable else { return }
        generation += 1
        let mine = generation
        let (scope, week) = (self.scope, self.week)
        phase = .loading
        errorText = nil
        do {
            let loaded = try await env.play.call { try await $0.leaderboard(scope: scope, week: week) }
            guard !Task.isCancelled, mine == generation else { return }
            board = loaded
            profileIsPrivate = false
            phase = .loaded
            if scope == .global, let you = loaded.you, you.optedIn, you.rank == nil, env.social.isAvailable {
                let own = try? await env.social.call { try await $0.profile() }
                guard !Task.isCancelled, mine == generation else { return }
                profileIsPrivate = own?.visibility == .private
            }
            if emitView { emit(.playBoardView(scope: scope.rawValue)) }
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            phase = .failed
        }
    }

    /// Sets `leaderboard_opt_in` on the caller's existing profile (needs `features.social`), then reloads the board.
    func join() async {
        guard optIn == .join, !joining else { return }
        joining = true
        errorText = nil
        defer { joining = false }
        do {
            _ = try await env.social.call { try await $0.saveProfile(ProfilePatch(leaderboardOptIn: true)) }
            await load(emitView: false)
        } catch is CancellationError {
            return
        } catch {
            errorText = PlayMessage.text(for: error)
        }
    }

    /// Opens the profile editor (to create the profile, or to make it visible).
    func createProfile() {
        env.router.open(.profileEditor)
    }
}
