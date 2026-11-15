import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerData
import VoyagerModel

/// What the Watch buttons know, kept apart from `WatchCreateCoordinator`'s stored properties so SwiftUI can observe it.
@MainActor @Observable
final class QuickWatchStore {
    struct Known: Equatable {
        var id: Int
        var pending: Bool
    }

    private(set) var known: [WatchRequest: Known] = [:]
    /// `409 watch_limit` came back and nothing was created since.
    var limitReached = false
    /// `503 live_prices_off` came back this session although `/config` said otherwise.
    var livePricesOff = false
    /// Watches this session created with a one-tap watch and may still undo, with the tap's surface.
    @ObservationIgnored private(set) var undoable: [UndoKey: QuickWatchSurface] = [:]

    struct UndoKey: Hashable {
        var kind: WatchKind
        var id: Int
    }

    func remember(_ request: WatchRequest, id: Int, pending: Bool) {
        known[request] = Known(id: id, pending: pending)
        limitReached = false
    }

    func allowUndo(kind: WatchKind, id: Int, surface: QuickWatchSurface) {
        undoable[UndoKey(kind: kind, id: id)] = surface
    }

    func takeUndo(kind: WatchKind, id: Int) -> QuickWatchSurface? {
        undoable.removeValue(forKey: UndoKey(kind: kind, id: id))
    }

    func forget(kind: WatchKind, id: Int) {
        for (request, entry) in known where request.kind == kind && entry.id == id { known[request] = nil }
    }
}

extension WatchCreateCoordinator {
    /// The button state of `request` (plan Task 3.4): hidden without live prices, "Watching" once started,
    /// "Already watching" for an existing watch, and a limit state after `409 watch_limit`.
    public func state(for request: WatchRequest) -> QuickWatchState {
        if quick.livePricesOff { return .off }
        if let config = env.clientConfig, config.features["live_prices"] != nil,
            !RemoteFeatures(config: config).livePrices
        {
            return .off
        }
        if let entry = quick.known[request] { return entry.pending ? .pending(entry.id) : .existing(entry.id) }
        return quick.limitReached ? .limit : .idle
    }

    /// A watch was created, changed or deleted somewhere: the shared limit may have room again.
    func watchesDidChange() { quick.limitReached = false }

    public func canUndo(kind: WatchKind, id: Int) -> Bool {
        quick.undoable[QuickWatchStore.UndoKey(kind: kind, id: id)] != nil
    }

    /// Removes the watch a one-tap watch just created. False when it could not be removed.
    public func undo(kind: WatchKind, id: Int) async -> Bool {
        guard let surface = quick.takeUndo(kind: kind, id: id) else { return false }
        do {
            try await env.repos.watches.delete(kind: kind, id: id)
        } catch {
            quick.allowUndo(kind: kind, id: id, surface: surface)
            return false
        }
        quick.forget(kind: kind, id: id)
        track(.alertQuickWatch(kind: kind.rawValue, action: "undo", surface: surface.rawValue))
        await env.watchesChanged()
        return true
    }

    // MARK: One-tap path

    /// `POST /alerts/quick-watch`. Nil means "use the older flow": the route turned out to be missing.
    func quickHandle(_ request: WatchRequest, surface: QuickWatchSurface) async -> WatchCreateResult? {
        let kind = request.kind
        let draft = QuickWatchDraft(request)
        let body = QuickWatchRequest(
            kind: kind, title: draft.title, subtitle: draft.subtitle, spec: request.spec,
            planId: request.spec["plan_id"].int, surface: surface)
        do {
            let result = try await env.alertsV2.quickWatch(body)
            let pending = result.watch.pendingFirstCheck
            quick.remember(request, id: result.watchID, pending: pending)
            if result.existing {
                track(.alertQuickWatch(kind: kind.rawValue, action: "exists", surface: surface.rawValue))
                return .alreadyWatching(kind, result.watchID)
            }
            quick.allowUndo(kind: kind, id: result.watchID, surface: surface)
            track(.alertQuickWatch(kind: kind.rawValue, action: "add", surface: surface.rawValue))
            track(.alertEvent(action: "watch_create", kind: kind.rawValue))
            return .quickCreated(kind, result.watchID)
        } catch is AlertsV2Service.Unavailable {
            return nil
        } catch let error as APIError {
            if AlertsV2Failure.isRouteMissing(error) { return nil }
            guard let failure = AlertsV2Failure.from(error, call: .quickWatch) else { return .failed(error) }
            switch failure {
            case .watchLimit: quick.limitReached = true
            case .livePricesOff: quick.livePricesOff = true
            default: break
            }
            track(.alertQuickWatch(kind: kind.rawValue, action: "blocked", surface: surface.rawValue))
            return .refused(Self.message(for: failure))
        } catch {
            return .failed(.network)
        }
    }

    /// The translated copy of a refusal (`quickWatch:error.*`); everything else is the generic line.
    static func message(for failure: AlertsV2Failure) -> String {
        switch failure {
        case .watchLimit: L10n.text(K.quickWatch.error.watch_limit)
        case .livePricesOff: L10n.text(K.quickWatch.error.live_prices_off)
        case .specInvalid: L10n.text(K.quickWatch.error.spec_invalid)
        default: L10n.text(K.quickWatch.error.generic)
        }
    }
}

extension WatchItem {
    /// Whether the server still has to make the first check.
    var pendingFirstCheck: Bool {
        switch self {
        case .fare(let watch): watch.pendingFirstCheck ?? false
        case .price(let watch): watch.pendingFirstCheck ?? false
        }
    }
}

/// The title and subtitle a one-tap watch needs, taken from the spec the card handed over.
struct QuickWatchDraft: Equatable {
    var title: String
    var subtitle: String?

    init(_ request: WatchRequest) {
        let spec = request.spec
        func text(_ key: String) -> String? {
            spec[key].string?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        func dates(_ from: String, _ to: String) -> String? {
            switch (text(from), text(to)) {
            case (let a?, let b?): "\(a) – \(b)"
            case (let a?, nil): a
            default: nil
            }
        }
        switch request.kind {
        case .flight:
            let route = [text("origin"), text("destination")].compactMap { $0 }
            title = route.joined(separator: " → ")
            subtitle = dates("departure_date", "return_date")
        case .hotel:
            title = text("name") ?? ""
            subtitle = [text("city"), dates("check_in", "check_out")].compactMap { $0 }.joined(separator: " · ").nonEmpty
        case .activity:
            title = text("name") ?? ""
            subtitle = text("city")
        case .trip:
            title = text("name") ?? text("title") ?? text("destination") ?? ""
            subtitle = text("subtitle") ?? dates("departure_date", "return_date")
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
