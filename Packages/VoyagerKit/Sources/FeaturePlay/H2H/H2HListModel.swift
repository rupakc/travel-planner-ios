import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// The head-to-head part of the Play hub: the caller's matches and the "challenge a friend by handle" form. The server
/// owns every state, score and limit; the app lists what it is told and sends the handle and pack.
@MainActor @Observable
final class H2HListModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The list could not be loaded; the form still works.
        case failed
    }

    /// The four practice packs a match can be about.
    static let packs = ["flags", "capitals", "landmarks", "cuisine"]

    private(set) var phase: Phase = .loading
    private(set) var matches: [H2HMatch] = []
    var handle = ""
    var pack = "flags"
    private(set) var creating = false
    private(set) var errorText: String?

    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    /// Called when a quiz was opened from here, so the hub reloads on return.
    @ObservationIgnored var didOpenQuiz: @MainActor () -> Void = {}

    init(env: AppEnvironment, track: @escaping @MainActor (TelemetryEvent) -> Void) {
        self.env = env
        self.emit = track
    }

    /// The typed handle without spaces and a leading `@`.
    var cleanHandle: String {
        var text = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("@") { text.removeFirst() }
        return text
    }

    var canCreate: Bool { !cleanHandle.isEmpty && !creating }

    func load() async {
        guard env.play.isAvailable else { return }
        do {
            let loaded = try await env.play.call { try await $0.matches() }
            guard !Task.isCancelled else { return }
            matches = loaded
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            // `403 game_hidden` and a feature-off 404 are noticed by the hub through `env.play.isAvailable`.
            if phase != .loaded { phase = .failed }
        }
    }

    func open(_ match: H2HMatch) {
        didOpenQuiz()
        env.router.open(.h2h(id: match.id))
    }

    func create() async {
        let target = cleanHandle
        guard !target.isEmpty, !creating else { return }
        creating = true
        errorText = nil
        defer { creating = false }
        let chosen = pack
        do {
            let session = try await env.play.call { try await $0.challenge(handle: target, pack: chosen) }
            emit(.playH2HCreate)
            emit(.playQuizStart(mode: "h2h", pack: chosen))
            handle = ""
            didOpenQuiz()
            env.router.open(.quiz(sessionID: session.sessionID))
        } catch is CancellationError {
            return
        } catch {
            if !(error is PlayService.Unavailable) { errorText = PlayMessage.text(for: error) }
        }
    }
}
