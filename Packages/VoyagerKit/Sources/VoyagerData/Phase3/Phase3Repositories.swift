import Foundation
import Networking
import VoyagerModel

// Price alerts 2.0 (`docs/Alerts-API.md`) routes. No SerpAPI or price source is ever called from the app: every number
// comes from these routes.
extension Endpoints {
    public static func alertsSummary() -> Endpoint<Savings> {
        Endpoint(path: "/api/alerts/summary", telemetryName: "/api/alerts/summary")
    }

    public static func alertsStory(kind: WatchKind, id: Int) -> Endpoint<PriceStory> {
        Endpoint(
            path: "/api/alerts/watches/\(kind.rawValue)/\(id)/story", telemetryName: "/api/alerts/watches/:kind/:id/story")
    }

    public static func alertsAdvice(kind: WatchKind, id: Int) -> Endpoint<AdviceTip> {
        Endpoint(
            method: .post, path: "/api/alerts/watches/\(kind.rawValue)/\(id)/advice",
            telemetryName: "/api/alerts/watches/:kind/:id/advice", timeout: .ai)
    }

    public static func alertsQuickWatch(_ request: QuickWatchRequest) -> Endpoint<QuickWatchResult> {
        Endpoint(method: .post, path: "/api/alerts/quick-watch", telemetryName: "/api/alerts/quick-watch", body: request)
    }

    public static func alertsSuggestions(planID: Int) -> Endpoint<WatchSuggestions> {
        Endpoint(
            path: "/api/alerts/suggestions", telemetryName: "/api/alerts/suggestions",
            query: [URLQueryItem(name: "plan_id", value: String(planID))])
    }

    public static func alertsPrefs() -> Endpoint<AlertPrefs> {
        Endpoint(path: "/api/alerts/preferences", telemetryName: "/api/alerts/preferences")
    }

    public static func updateAlertsPrefs(_ patch: AlertPrefsPatch) -> Endpoint<AlertPrefs> {
        Endpoint(method: .put, path: "/api/alerts/preferences", telemetryName: "/api/alerts/preferences", body: patch)
    }
}

public struct LiveAlertsV2Repository: AlertsV2Repository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func summary() async throws -> Savings { try await api.send(Endpoints.alertsSummary()) }
    public func story(kind: WatchKind, id: Int) async throws -> PriceStory { try await api.send(Endpoints.alertsStory(kind: kind, id: id)) }
    public func advice(kind: WatchKind, id: Int) async throws -> AdviceTip {
        try await api.send(Endpoints.alertsAdvice(kind: kind, id: id))
    }
    public func quickWatch(_ request: QuickWatchRequest) async throws -> QuickWatchResult {
        try await api.send(Endpoints.alertsQuickWatch(request))
    }
    public func suggestions(planID: Int) async throws -> WatchSuggestions {
        try await api.send(Endpoints.alertsSuggestions(planID: planID))
    }
    public func prefs() async throws -> AlertPrefs { try await api.send(Endpoints.alertsPrefs()) }
    public func updatePrefs(_ patch: AlertPrefsPatch) async throws -> AlertPrefs { try await api.send(Endpoints.updateAlertsPrefs(patch)) }
}

/// Which Phase 3 call failed; the same status means different things per call (a 503 is `ai_limit` for advice and
/// `live_prices_off` for a quick watch).
public enum AlertsV2Call: Sendable, Hashable {
    case summary, story, advice, quickWatch, suggestions, prefs, updatePrefs
}

/// The error codes of `Alerts-API.md` that clients translate. Everything else keeps the backend `detail`.
public enum AlertsV2Failure: String, Error, Sendable, Hashable, CaseIterable {
    case watchNotFound = "watch_not_found"
    case kindInvalid = "kind_invalid"
    case adviceUnsupported = "advice_unsupported"
    case adviceNoData = "advice_no_data"
    case adviceFailed = "advice_failed"
    case aiLimit = "ai_limit"
    case aiBilling = "ai_billing"
    case livePricesOff = "live_prices_off"
    case watchLimit = "watch_limit"
    case specInvalid = "spec_invalid"
    case tripNotFound = "trip_not_found"
    case alertPrefsInvalid = "alert_prefs_invalid"

    /// The translated code of `error` for `call`, or nil when it is not one of ours (429, network, an unknown code).
    /// The error envelope is `{"detail", "error_code"}`; `ErrorMapping` drops the body of 404 and 5xx answers, so those
    /// are read from the call and the status.
    public static func from(_ error: APIError, call: AlertsV2Call) -> AlertsV2Failure? {
        switch error {
        case .client(_, _, let code, let body):
            let raw = body["error_code"].string ?? code ?? body["detail"]["error_code"].string
            return raw.flatMap(AlertsV2Failure.init(rawValue:))
        case .notFound:
            switch call {
            case .suggestions: return .tripNotFound
            case .story, .advice: return .watchNotFound
            default: return nil
            }
        case .server(let status, _, let code):
            if let code, let failure = AlertsV2Failure(rawValue: code) { return failure }
            // A 5xx without a readable code: read it from the call and status.
            switch (call, status) {
            case (.advice, 502): return .adviceFailed
            case (.advice, 503): return .aiLimit
            case (.quickWatch, 503): return .livePricesOff
            default: return nil
            }
        default:
            return nil
        }
    }

    /// A 404 that is the route itself missing (FastAPI's `{"detail": "Not Found"}`), not one of our coded answers.
    public static func isRouteMissing(_ error: APIError) -> Bool {
        if case .notFound(let detail) = error { return detail == nil || detail == "Not Found" }
        return false
    }
}
