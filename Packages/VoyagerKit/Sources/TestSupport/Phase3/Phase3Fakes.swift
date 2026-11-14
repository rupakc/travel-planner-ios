import VoyagerModel

/// A scripted `AlertsV2Repository`. Unscripted story/advice/quick-watch/suggestions calls throw
/// `FakeRepositoryError.notScripted`; the summary and prefs default to empty ones.
public final class FakeAlertsV2Repository: AlertsV2Repository {
    public let onSummary = FakeCall<Void, Savings>("alertsV2.summary") { _ in Savings() }
    public let onStory = FakeCall<(kind: WatchKind, id: Int), PriceStory>("alertsV2.story")
    public let onAdvice = FakeCall<(kind: WatchKind, id: Int), AdviceTip>("alertsV2.advice")
    public let onQuickWatch = FakeCall<QuickWatchRequest, QuickWatchResult>("alertsV2.quickWatch")
    public let onSuggestions = FakeCall<Int, WatchSuggestions>("alertsV2.suggestions")
    public let onPrefs = FakeCall<Void, AlertPrefs>("alertsV2.prefs") { _ in AlertPrefs() }
    public let onUpdatePrefs = FakeCall<AlertPrefsPatch, AlertPrefs>("alertsV2.updatePrefs")
    public init() {}

    public func summary() async throws -> Savings { try await onSummary() }
    public func story(kind: WatchKind, id: Int) async throws -> PriceStory { try await onStory((kind, id)) }
    public func advice(kind: WatchKind, id: Int) async throws -> AdviceTip { try await onAdvice((kind, id)) }
    public func quickWatch(_ request: QuickWatchRequest) async throws -> QuickWatchResult { try await onQuickWatch(request) }
    public func suggestions(planID: Int) async throws -> WatchSuggestions { try await onSuggestions(planID) }
    public func prefs() async throws -> AlertPrefs { try await onPrefs() }
    public func updatePrefs(_ patch: AlertPrefsPatch) async throws -> AlertPrefs { try await onUpdatePrefs(patch) }
}
