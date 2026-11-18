import Foundation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The writes of an idea (like, save, delete, report, block), shared by the feed and the idea screen. Each goes
/// through `SocialService` (never a route whose flag is off) and emits its telemetry only after the server accepted it.
@MainActor
struct IdeaActions {
    let env: AppEnvironment
    let emit: @MainActor (TelemetryEvent) -> Void

    init(env: AppEnvironment, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    /// Like and unlike are idempotent on the server, so a repeated call is harmless.
    func setLike(_ id: String, on: Bool) async throws {
        try await env.social.call { repository in
            if on {
                try await repository.like(ideaID: id)
            } else {
                try await repository.unlike(ideaID: id)
            }
        }
        emit(.socialIdeaLike(on: on))
    }

    /// Remixes the idea into a new plan of the caller's and returns its id (saving again returns the existing copy).
    func save(_ id: String) async throws -> Int {
        let planID = try await env.social.call { try await $0.save(ideaID: id) }
        emit(.socialIdeaSave)
        return planID
    }

    /// Forgets the save mark; the copied plan stays.
    func forgetSave(_ id: String) async throws {
        try await env.social.call { try await $0.forgetSave(ideaID: id) }
    }

    func delete(_ id: String) async throws {
        try await env.social.call { try await $0.deleteIdea(id: id) }
        env.social.ledger.deleted(ideaID: id)
    }

    func report(_ request: ReportRequest) async throws {
        try await env.social.call { try await $0.report(request) }
        emit(.socialReport(target: request.target.rawValue, reason: request.reason.rawValue))
    }

    func block(_ handle: String) async throws {
        try await env.social.call { try await $0.block(handle: handle) }
        env.social.ledger.blocked(handle: handle)
    }
}
