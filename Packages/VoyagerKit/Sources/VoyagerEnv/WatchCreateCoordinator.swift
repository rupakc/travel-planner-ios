import Foundation
import L10n
import Networking
import VoyagerModel

/// What a "Watch price" tap produced.
public enum WatchCreateResult: Sendable, Equatable {
    case created(WatchKind, Int)
    case alreadyWatching(WatchKind, Int)
    /// `422 no_live_price`, with the copy to show.
    case noLivePrice(String)
    case failed(APIError)
}

/// Serves watch requests from Results and Chat: asks the server whether the caller already watches the subject
/// (`match`, no live lookup), and only then creates the watch. Telemetry carries the action and kind only.
@MainActor
public final class WatchCreateCoordinator {
    private unowned let env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
    }

    public func handle(_ request: WatchRequest) async -> WatchCreateResult {
        let kind = request.kind
        let planId = request.spec["plan_id"].int
        let repo = env.repos.watches
        // A failed match is not fatal: the server matches again on create and answers `already_watching`.
        if let existing = try? await repo.match(WatchMatchQuery(kind: kind, spec: request.spec, planId: planId)),
            !existing.isNull, let id = existing["id"].int
        {
            return .alreadyWatching(kind, id)
        }
        do {
            let created = try await create(request, planId: planId)
            env.telemetry.track(.alertEvent(action: "watch_create", kind: kind.rawValue))
            return created.existing ? .alreadyWatching(kind, created.id) : .created(kind, created.id)
        } catch let error as APIError {
            if let copy = Self.noLivePriceCopy(error, kind: kind) { return .noLivePrice(copy) }
            return .failed(error)
        } catch {
            return .failed(.network)
        }
    }

    private func create(_ request: WatchRequest, planId: Int?) async throws -> (id: Int, existing: Bool) {
        let repo = env.repos.watches
        switch request {
        case .fare(let spec):
            let watch = try await repo.createFare(
                NewFareWatch(
                    planId: planId,
                    origin: spec["origin"].string,
                    destination: spec["destination"].string,
                    departureDate: spec["departure_date"].string,
                    returnDate: spec["return_date"].string,
                    numTravelers: spec["num_travelers"].int,
                    alertMode: "any_drop"))
            return (watch.id, watch.alreadyWatching ?? false)
        case .hotel, .activity, .trip:
            let watch = try await repo.createPrice(
                NewPriceWatch(kind: request.kind, spec: request.spec, planId: planId, alertMode: "any_drop"))
            return (watch.id, watch.alreadyWatching ?? false)
        }
    }

    /// The copy for `422 no_live_price`: the server's own message when it sent one, else the catalogue's
    /// "couldn't start watching" line for the kind. Nil for any other error.
    static func noLivePriceCopy(_ error: APIError, kind: WatchKind) -> String? {
        guard case .client(let status, let detail, let code, let body) = error, status == 422,
            (code ?? body["code"].string) == "no_live_price"
        else { return nil }
        for candidate in [body["message"].string, detail] {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        switch kind {
        case .flight: return L10n.text(K.alerts.dialog.fare.startFailed)
        case .hotel: return L10n.text(K.alerts.dialog.price.failed.hotel)
        case .activity: return L10n.text(K.alerts.dialog.price.failed.activity)
        case .trip: return L10n.text(K.alerts.dialog.price.failed.trip)
        }
    }
}
