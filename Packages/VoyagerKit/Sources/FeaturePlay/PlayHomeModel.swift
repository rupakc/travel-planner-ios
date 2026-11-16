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

    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    /// Set when a quiz was opened: the hub reloads when it comes back to the front.
    @ObservationIgnored private var needsRefresh = false

    init(env: AppEnvironment, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    var daily: DailyQuizState { state.daily }
    var packs: [QuizPack] { state.packs }
    var challenge: PlayChallenge? { state.challenge }
    var openMatches: Int { state.openH2H }
    var isBusy: Bool { starting != nil }

    func load() async {
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

    /// Called when the hub is shown again (after a quiz): a quiz finished meanwhile changes today's card.
    func refreshIfNeeded() async {
        guard needsRefresh else { return }
        needsRefresh = false
        await load()
    }

    func startDaily() async {
        await start(QuizStart(mode: .daily), key: "daily")
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
