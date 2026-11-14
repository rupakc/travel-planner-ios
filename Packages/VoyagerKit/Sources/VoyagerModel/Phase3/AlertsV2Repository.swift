import Foundation

/// The Phase 3 routes of `docs/Alerts-API.md`. Calls are made only when the matching `RemoteFeatures` flag is on.
public protocol AlertsV2Repository: Sendable {
    func summary() async throws -> Savings
    func story(kind: WatchKind, id: Int) async throws -> PriceStory
    /// Flights only (`422 advice_unsupported` otherwise).
    func advice(kind: WatchKind, id: Int) async throws -> AdviceTip
    func quickWatch(_ request: QuickWatchRequest) async throws -> QuickWatchResult
    func suggestions(planID: Int) async throws -> WatchSuggestions
    func prefs() async throws -> AlertPrefs
    func updatePrefs(_ patch: AlertPrefsPatch) async throws -> AlertPrefs
}
