import Foundation
import Networking
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@MainActor
@Suite struct AlertsV2ServiceTests {
    private func config(alertsAPI: Int = 2, v2: Bool = true, live: Bool = true) -> ClientConfig {
        ClientConfig(features: ["alerts_api": .number(Double(alertsAPI)), "price_alerts_v2": .bool(v2), "live_prices": .bool(live)])
    }

    private let request = QuickWatchRequest(
        kind: .hotel, title: "Lumen Hotel", spec: ["name": "Lumen Hotel"], planId: 3, surface: .results)

    private func result(existing: Bool) -> QuickWatchResult {
        QuickWatchResult(
            kind: .hotel, watch: .price(PriceWatch(id: 41, kind: .hotel, pendingFirstCheck: true)), existing: existing)
    }

    @Test func test_olderBackendNeverCallsAnyRoute() async {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes)  // no /config: every flag is off
        await #expect(throws: AlertsV2Service.Unavailable.self) { try await env.alertsV2.summary() }
        await #expect(throws: AlertsV2Service.Unavailable.self) { try await env.alertsV2.story(kind: .flight, id: 1) }
        await #expect(throws: AlertsV2Service.Unavailable.self) { try await env.alertsV2.quickWatch(request) }
        #expect(fakes.alertsV2.onSummary.callCount == 0 && fakes.alertsV2.onStory.callCount == 0)
        #expect(fakes.alertsV2.onQuickWatch.callCount == 0)
        #expect(!env.alertsV2.isAvailable(.stored) && !env.alertsV2.isAvailable(.quickWatch))
    }

    @Test func test_quickWatchNeedsLivePricesButStoriesDoNot() async throws {
        let fakes = FakeRepositories()
        fakes.alertsV2.onSummary.returns(Savings(totalUSD: 12))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config(live: false))
        #expect(env.alertsV2.isAvailable(.stored) && !env.alertsV2.isAvailable(.quickWatch))
        #expect(try await env.alertsV2.summary().totalUSD == 12)
        await #expect(throws: AlertsV2Service.Unavailable.self) { try await env.alertsV2.suggestions(planID: 3) }
        await #expect(throws: AlertsV2Service.Unavailable.self) { try await env.alertsV2.quickWatch(request) }
        #expect(fakes.alertsV2.onQuickWatch.callCount == 0 && fakes.alertsV2.onSuggestions.callCount == 0)
    }

    @Test func test_newQuickWatchFiresTheWatchesChangedHookOnce() async throws {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.returns(result(existing: false))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        var calls = 0
        env.onWatchesChanged = { calls += 1 }
        let created = try await env.alertsV2.quickWatch(request)
        #expect(!created.existing && created.watchID == 41)
        #expect(calls == 1)
        #expect(fakes.alertsV2.onQuickWatch.lastCall == request)
    }

    @Test func test_existingOrFailedQuickWatchDoesNotFireTheHook() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.returns(result(existing: true))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        var calls = 0
        env.onWatchesChanged = { calls += 1 }
        _ = try? await env.alertsV2.quickWatch(request)
        fakes.alertsV2.onQuickWatch.fails(APIError.client(status: 409, detail: "limit", code: "watch_limit", body: .null))
        _ = try? await env.alertsV2.quickWatch(request)
        #expect(calls == 0)
    }

    @Test func test_missingRouteTurnsTheFeatureOffForTheSession() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onSummary.fails(APIError.notFound("Not Found"))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        await #expect(throws: APIError.self) { try await env.alertsV2.summary() }
        #expect(!env.alertsV2.isAvailable(.stored))
        await #expect(throws: AlertsV2Service.Unavailable.self) { try await env.alertsV2.summary() }
        #expect(fakes.alertsV2.onSummary.callCount == 1)
    }

    @Test func test_codedNotFoundKeepsTheFeatureOn() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onStory.fails(APIError.notFound("Watch not found"))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        await #expect(throws: APIError.self) { try await env.alertsV2.story(kind: .flight, id: 9) }
        #expect(env.alertsV2.isAvailable(.stored))
    }
}
