import Foundation
import Networking
import VoyagerData
import VoyagerModel

/// What a Phase 3 call needs from the server.
public enum AlertsV2Feature: Sendable, Hashable, CaseIterable {
    /// Stories, advice, savings and prefs: `alerts_api >= 2`.
    case stored
    /// One-tap watch and suggestions: `live_prices` and (`price_alerts_v2` or `alerts_api >= 2`), plan ruling R3.
    case quickWatch
}

/// The one door to the Phase 3 routes. It never calls a route whose flag is off (an older backend keeps today's
/// screens, silently), and a 404 that means "no such route" (a stale `/config`, cached 5 min) turns that feature off
/// for the session instead of retrying. A one-tap watch fires `watchesChanged()` like every other watch create.
@MainActor
public final class AlertsV2Service {
    /// Thrown instead of calling a route whose flag is off.
    public struct Unavailable: Error, Equatable, Sendable {}

    private unowned let env: AppEnvironment
    private var degraded: Set<AlertsV2Feature> = []

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var features: RemoteFeatures { RemoteFeatures(config: env.clientConfig) }

    public func isAvailable(_ feature: AlertsV2Feature) -> Bool {
        guard !degraded.contains(feature) else { return false }
        switch feature {
        case .stored: return features.hasAlertsV2
        case .quickWatch: return features.showsQuickWatch && features.hasAlertsV2
        }
    }

    // MARK: Stored-data reads (no live prices needed)

    public func summary() async throws -> Savings {
        try await run(.stored, .summary) { try await $0.summary() }
    }

    public func story(kind: WatchKind, id: Int) async throws -> PriceStory {
        try await run(.stored, .story) { try await $0.story(kind: kind, id: id) }
    }

    public func advice(kind: WatchKind, id: Int) async throws -> AdviceTip {
        try await run(.stored, .advice) { try await $0.advice(kind: kind, id: id) }
    }

    public func prefs() async throws -> AlertPrefs {
        try await run(.stored, .prefs) { try await $0.prefs() }
    }

    public func updatePrefs(_ patch: AlertPrefsPatch) async throws -> AlertPrefs {
        try await run(.stored, .updatePrefs) { try await $0.updatePrefs(patch) }
    }

    // MARK: Needs live prices

    public func suggestions(planID: Int) async throws -> WatchSuggestions {
        try await run(.quickWatch, .suggestions) { try await $0.suggestions(planID: planID) }
    }

    /// Creates a pending watch. A new one (not `existing`) fires `AppEnvironment.watchesChanged()`, so the local
    /// reminders and the alert poll refresh; an existing one changed nothing.
    public func quickWatch(_ request: QuickWatchRequest) async throws -> QuickWatchResult {
        let result = try await run(.quickWatch, .quickWatch) { try await $0.quickWatch(request) }
        if !result.existing { await env.watchesChanged() }
        return result
    }

    // MARK: Plumbing

    private func run<T>(
        _ feature: AlertsV2Feature, _ call: AlertsV2Call, _ operation: (any AlertsV2Repository) async throws -> T
    ) async throws -> T {
        guard isAvailable(feature) else { throw Unavailable() }
        do {
            return try await operation(env.repos.alertsV2)
        } catch let error as APIError {
            if AlertsV2Failure.isRouteMissing(error) { degraded.insert(feature) }
            throw error
        }
    }
}
