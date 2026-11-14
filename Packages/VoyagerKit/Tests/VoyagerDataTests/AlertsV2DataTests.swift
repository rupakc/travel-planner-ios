import Foundation
import Networking
import Testing
import VoyagerModel

@testable import VoyagerData

struct AlertsV2DataTests {
    @Test func test_routes() {
        let story = Endpoints.alertsStory(kind: .hotel, id: 3)
        #expect(story.method == .get && story.path == "/api/alerts/watches/hotel/3/story" && story.auth == .required)
        let advice = Endpoints.alertsAdvice(kind: .flight, id: 7)
        #expect(advice.method == .post && advice.path == "/api/alerts/watches/flight/7/advice" && advice.timeout == .ai)
        #expect(Endpoints.alertsSummary().path == "/api/alerts/summary")
        let quick = Endpoints.alertsQuickWatch(QuickWatchRequest(kind: .hotel, title: "Lumen", spec: .object([:]), surface: .results))
        #expect(quick.method == .post && quick.path == "/api/alerts/quick-watch")
        let suggestions = Endpoints.alertsSuggestions(planID: 12)
        #expect(suggestions.path == "/api/alerts/suggestions" && suggestions.query == [URLQueryItem(name: "plan_id", value: "12")])
        #expect(Endpoints.alertsPrefs().path == "/api/alerts/preferences")
        #expect(Endpoints.updateAlertsPrefs(AlertPrefsPatch()).method == .put)
    }

    @Test func test_telemetryNamesCarryNoIds() {
        let names = [
            Endpoints.alertsStory(kind: .trip, id: 99).telemetryName,
            Endpoints.alertsAdvice(kind: .flight, id: 99).telemetryName,
            Endpoints.alertsSuggestions(planID: 99).telemetryName,
        ]
        for name in names { #expect(!name.contains("99") && !name.contains("trip")) }
    }

    @Test func test_failureCodesAreReadFromTheEnvelopeOrTheCall() {
        func client(_ code: String) -> APIError {
            .client(status: 422, detail: "x", code: code, body: .object(["error_code": .string(code)]))
        }
        #expect(AlertsV2Failure.from(client("spec_invalid"), call: .quickWatch) == .specInvalid)
        #expect(AlertsV2Failure.from(client("watch_limit"), call: .quickWatch) == .watchLimit)
        #expect(AlertsV2Failure.from(client("advice_no_data"), call: .advice) == .adviceNoData)
        #expect(AlertsV2Failure.from(client("alert_prefs_invalid"), call: .updatePrefs) == .alertPrefsInvalid)
        #expect(AlertsV2Failure.from(client("something_new"), call: .story) == nil)
        #expect(AlertsV2Failure.from(.notFound(nil), call: .suggestions) == .tripNotFound)
        #expect(AlertsV2Failure.from(.notFound(nil), call: .story) == .watchNotFound)
        #expect(AlertsV2Failure.from(.server(status: 503, detail: nil), call: .quickWatch) == .livePricesOff)
        #expect(AlertsV2Failure.from(.server(status: 503, detail: nil), call: .advice) == .aiLimit)
        #expect(AlertsV2Failure.from(.server(status: 502, detail: nil), call: .advice) == .adviceFailed)
        #expect(AlertsV2Failure.from(.rateLimited(message: "slow down", retryAfter: 5), call: .advice) == nil)
        #expect(AlertsV2Failure.from(.network, call: .summary) == nil)
    }

    @Test func test_bareNotFoundIsAMissingRoute() {
        #expect(AlertsV2Failure.isRouteMissing(.notFound("Not Found")))
        #expect(AlertsV2Failure.isRouteMissing(.notFound(nil)))
        #expect(!AlertsV2Failure.isRouteMissing(.notFound("Watch not found")))
        #expect(!AlertsV2Failure.isRouteMissing(.network))
    }
}
