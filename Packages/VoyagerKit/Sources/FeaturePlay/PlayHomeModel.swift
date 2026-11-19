import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// The Play hub: today's quiz, the practice packs, the weekly challenge, open head-to-head matches and recent games.
/// Starting a quiz creates the session on the server and opens it on the quiz screen (`Route.quiz`), which also resumes it.
@MainActor @Observable
final class PlayHomeModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The route is off, the account hides the game, or the flag is 0: the hub says so and offers nothing.
        case unavailable(gameHidden: Bool)
        case failed(kind: ErrorPresentationKind, detail: String?)
    }

    private(set) var phase: Phase = .loading
    private(set) var state = PlayState()
    private(set) var history: [QuizHistoryEntry] = []
    /// `daily`, `challenge` or a pack id while its session is being created.
    private(set) var starting: String?
    private(set) var errorText: String?

    /// Head-to-head matches and the weekly board: parts of the hub with their own loading and failures.
    let h2h: H2HListModel
    let board: BoardModel

    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    /// Set when a quiz was opened: the hub reloads when it comes back to the front.
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(env: AppEnvironment, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        let telemetry = env.telemetry
        let emit: @MainActor (TelemetryEvent) -> Void = track ?? { telemetry.track($0) }
        self.emit = emit
        self.h2h = H2HListModel(env: env, track: emit)
        self.board = BoardModel(env: env, track: emit)
        h2h.didOpenQuiz = { [weak self] in self?.needsRefresh = true }
    }

    var daily: DailyQuizState { state.daily }
    var packs: [QuizPack] { state.packs }
    var challenge: PlayChallenge? { state.challenge }
    var openMatches: Int { state.openH2H }
    var isBusy: Bool { starting != nil }

    /// One load at a time: the view's `.task` and `.onAppear` both ask when the screen comes back, and a second call
    /// while one is running shares it instead of fetching everything again (the view counters would count twice).
    func load() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            await performLoad()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func performLoad() async {
        guard env.play.isAvailable else {
            phase = .unavailable(gameHidden: env.play.isHiddenByServer)
            return
        }
        if phase != .loaded { phase = .loading }
        do {
            let loaded = try await env.play.call { try await $0.state() }
            guard !Task.isCancelled else { return }
            state = loaded
            phase = .loaded
            emit(.playStateView)
            // Recent games are a nicety: a failure here leaves the list as it was.
            if let games = try? await env.play.call({ try await $0.history(limit: 5) }) { history = games }
            await loadParts()
        } catch is CancellationError {
            return
        } catch is PlayService.Unavailable {
            phase = .unavailable(gameHidden: env.play.isHiddenByServer)
        } catch let error as APIError {
            if case .cancelled = error { return }
            if PlayFailure.isGameHidden(error) || PlayFailure.isFeatureOff(error) {
                phase = .unavailable(gameHidden: PlayFailure.isGameHidden(error))
            } else {
                phase = .failed(kind: error.presentationKind, detail: error.userFacingDetail)
            }
        } catch {
            phase = .failed(kind: .other, detail: nil)
        }
    }

    /// The parts with their own routes: the challenge card, head-to-head and the board. A `403 game_hidden` on any Play
    /// route hides the whole hub.
    private func loadParts() async {
        if state.challenge != nil { emit(.playChallengeView) }
        await h2h.load()
        await board.load()
        if !env.play.isAvailable { phase = .unavailable(gameHidden: env.play.isHiddenByServer) }
    }

    /// Called when the hub is shown again (after a quiz): a quiz finished meanwhile changes today's card.
    func refreshIfNeeded() async {
        guard needsRefresh else { return }
        needsRefresh = false
        await load()
    }

    func startDaily() async {
        await start(QuizStart(mode: .daily), key: "daily")
    }

    func startChallenge() async {
        // One challenge a week: a finished one only shows its done state.
        guard challenge?.done != true else { return }
        await start(QuizStart(mode: .challenge), key: "challenge")
    }

    func startPack(_ pack: QuizPack) async {
        await start(QuizStart(mode: .pack, pack: pack.id), key: pack.id)
    }

    private func start(_ request: QuizStart, key: String) async {
        guard starting == nil else { return }
        starting = key
        errorText = nil
        defer { starting = nil }
        do {
            let session = try await env.play.call { try await $0.startQuiz(request) }
            emit(.playQuizStart(mode: request.mode.rawValue, pack: request.mode == .pack ? (request.pack ?? "none") : "none"))
            needsRefresh = true
            env.router.open(.quiz(sessionID: session.sessionID))
        } catch is CancellationError {
            return
        } catch {
            if let api = error as? APIError, PlayFailure.from(api) == .alreadyDone {
                // Another device finished it: show today's result instead of an empty card.
                await load()
            }
            if !env.play.isAvailable {
                phase = .unavailable(gameHidden: env.play.isHiddenByServer)
            } else {
                errorText = PlayMessage.text(for: error)
            }
        }
    }
}
