import Domain
import Foundation
import Networking
import Testing
import TestSupport
import VoyagerModel

@testable import VoyagerEnv

/// `CarbonService` is the footprint card's feature detection: no route call while `features.carbon` is off, a `404`
/// switches the card off for the session, any other failure keeps it on.
@MainActor
@Suite struct CarbonServiceTests {
    private func config(carbon: Int) -> ClientConfig {
        ClientConfig(features: ["carbon": .number(Double(carbon))])
    }

    private let body: JSONValue = ["legs": [], "diet": "mixed"]
    private let answer: JSONValue = ["total_kg": 12, "categories": [["key": "food", "kg": 12, "share": 1]]]

    @Test func test_flagOffOrMissingNeverCallsTheRoute() async {
        let fakes = FakeRepositories()
        fakes.carbon.onTrip.returns(answer)
        let missing = AppEnvironment.fake(fakes: fakes)  // no /config: every flag is off
        #expect(!missing.carbon.isAvailable)
        #expect(await missing.carbon.trip(body) == .gone)
        let off = AppEnvironment.fake(fakes: fakes, clientConfig: config(carbon: 0))
        #expect(!off.carbon.isAvailable)
        #expect(await off.carbon.trip(body) == .gone)
        #expect(fakes.carbon.onTrip.callCount == 0)
    }

    @Test func test_flagOnLoadsTheReport() async throws {
        let fakes = FakeRepositories()
        fakes.carbon.onTrip.returns(answer)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config(carbon: 1))
        #expect(env.carbon.isAvailable)
        let expected = try #require(CarbonReport(json: answer))
        #expect(await env.carbon.trip(body) == .loaded(expected))
        #expect(fakes.carbon.onTrip.lastCall == body)
    }

    @Test func test_notFoundTurnsTheCardOffForTheSession() async {
        let fakes = FakeRepositories()
        fakes.carbon.onTrip.fails(APIError.notFound("Not Found"))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config(carbon: 1))
        #expect(await env.carbon.trip(body) == .gone)
        #expect(!env.carbon.isAvailable)
        fakes.carbon.onTrip.returns(answer)
        #expect(await env.carbon.trip(body) == .gone)
        #expect(fakes.carbon.onTrip.callCount == 1)
    }

    @Test func test_otherFailuresKeepTheCardOn() async {
        let fakes = FakeRepositories()
        fakes.carbon.onTrip.fails(APIError.server(status: 500, detail: nil))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config(carbon: 1))
        #expect(await env.carbon.trip(body) == .failed)
        #expect(env.carbon.isAvailable)
        fakes.carbon.onTrip.returns(answer)
        #expect(await env.carbon.trip(body) != .gone)
        #expect(fakes.carbon.onTrip.callCount == 2)
    }

    @Test func test_anAnswerThatIsNotAnObjectFails() async {
        let fakes = FakeRepositories()
        fakes.carbon.onTrip.returns(["not", "an", "object"])
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config(carbon: 1))
        #expect(await env.carbon.trip(body) == .failed)
        #expect(env.carbon.isAvailable)
    }
}
