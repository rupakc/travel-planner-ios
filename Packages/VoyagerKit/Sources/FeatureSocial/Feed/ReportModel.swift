import Foundation
import Observation
import VoyagerEnv
import VoyagerModel

/// The report sheet of an idea or comment (`POST /social/reports`): one of the seven contract reasons (the web's
/// default is spam) and an optional note of at most 200 characters.
@MainActor @Observable
final class ReportModel {
    enum Phase: Equatable {
        case form
        case sending
        case sent
        case failed(IdeaFailure)
    }

    let target: ReportTarget
    let id: String
    var reason: ReportReason = .spam
    var note = "" {
        didSet { if note.count > ReportRequest.maxNote { note = String(note.prefix(ReportRequest.maxNote)) } }
    }
    private(set) var phase: Phase = .form

    @ObservationIgnored private let send: @MainActor (ReportRequest) async throws -> Void

    init(target: ReportTarget, id: String, send: @escaping @MainActor (ReportRequest) async throws -> Void) {
        self.target = target
        self.id = id
        self.send = send
    }

    /// A report that goes through the shared `IdeaActions` (telemetry included).
    convenience init(target: ReportTarget, id: String, env: AppEnvironment) {
        let actions = IdeaActions(env: env)
        self.init(target: target, id: id) { try await actions.report($0) }
    }

    var canSubmit: Bool { phase != .sending && phase != .sent }

    func submit() async {
        guard canSubmit else { return }
        phase = .sending
        do {
            try await send(ReportRequest(target: target, id: id, reason: reason, note: note))
            phase = .sent
        } catch is CancellationError {
            phase = .form
        } catch {
            phase = .failed(IdeaFailure(error))
        }
    }
}
