import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// One match (`router.open(.h2h(id:))`, also where a `quiz_h2h_*` notification lands): accept or decline an invitation,
/// see who is up, or read the finished result. There is no single-match route, so it reads `GET /play/h2h` and picks the
/// match out.
@MainActor @Observable
final class H2HMatchModel {
    enum Phase: Equatable {
        case loading
        case unavailable
        case missing
        case failed(String)
        case loaded
    }

    private(set) var phase: Phase = .loading
    private(set) var match: H2HMatch?
    private(set) var busy = false
    private(set) var errorText: String?
    /// True once the invitation was declined: the screen closes.
    private(set) var declined = false

    let matchID: String
    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var opened = false
    @ObservationIgnored private var resultSent = false
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(env: AppEnvironment, matchID: String, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.matchID = matchID
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    /// One load at a time: the view's `.task` and `.onAppear` both ask when the screen comes back, and a second call
    /// while one is running shares it instead of fetching everything again (the view counters would count twice).
    func load() async {
        if loading {
            // The running load belongs to the first caller's task, so leaving the screen cancels it there.
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        loading = true
        await performLoad()
        loading = false
        let released = waiters
        waiters = []
        for waiter in released { waiter.resume() }
    }

    private func performLoad() async {
        guard env.play.isAvailable else {
            phase = .unavailable
            return
        }
        if phase != .loaded { phase = .loading }
        do {
            let all = try await env.play.call { try await $0.matches() }
            guard !Task.isCancelled else { return }
            match = all.first { $0.id == matchID }
            phase = match == nil ? .missing : .loaded
            guard let match else { return }
            if !opened {
                opened = true
                emit(.playH2HOpen)
            }
            if match.state == .done, let winner = match.winner, !resultSent {
                resultSent = true
                emit(.playH2HResult(winner: winner.rawValue))
            }
        } catch is CancellationError {
            return
        } catch {
            if error is PlayService.Unavailable || !env.play.isAvailable {
                phase = .unavailable
            } else {
                phase = .failed(PlayMessage.text(for: error))
            }
        }
    }

    /// Reloads when the screen comes back after the quiz.
    func refreshIfNeeded() async {
        guard needsRefresh else { return }
        needsRefresh = false
        await load()
    }

    /// The caller already has a session for this match (the creator, who plays at once, or an opponent who accepted):
    /// the backend reports `waiting_you` until it is finished, and accept or decline would answer 404 / 409.
    var canContinue: Bool { match?.state == .waitingYou && match?.sessionID?.isEmpty == false && !busy }

    /// An invitation the caller has not accepted: no session yet.
    var canAnswer: Bool { match?.state == .waitingYou && match?.sessionID?.isEmpty != false && !busy }

    /// Resumes the caller's own unfinished session.
    func resume() {
        guard canContinue, let match, let session = match.sessionID else { return }
        emit(.playQuizStart(mode: "h2h", pack: Self.knownPack(match.pack)))
        needsRefresh = true
        env.router.open(.quiz(sessionID: session))
    }

    func accept() async {
        guard canAnswer, let match else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let id = match.id
            let session = try await env.play.call { try await $0.accept(matchID: id) }
            emit(.playQuizStart(mode: "h2h", pack: Self.knownPack(match.pack ?? session.pack)))
            needsRefresh = true
            env.router.open(.quiz(sessionID: session.sessionID))
        } catch is CancellationError {
            return
        } catch {
            if !(error is PlayService.Unavailable) { errorText = PlayMessage.text(for: error) }
        }
    }

    func decline() async {
        guard canAnswer, let match else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            let id = match.id
            try await env.play.call { try await $0.decline(matchID: id) }
            declined = true
        } catch is CancellationError {
            return
        } catch {
            if !(error is PlayService.Unavailable) { errorText = PlayMessage.text(for: error) }
        }
    }

    private static func knownPack(_ pack: String?) -> String {
        guard let pack, H2HListModel.packs.contains(pack) else { return "none" }
        return pack
    }
}
