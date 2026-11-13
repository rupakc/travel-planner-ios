import AuthCore
import Networking
import SectionsUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureResults

@MainActor
final class ResultsCommerceTests: XCTestCase {
    private let request = TravelSearchRequest(
        origin: "NYC", destination: "Tokyo", departureDate: "2026-04-01", returnDate: "2026-04-08")

    private func make(user: User? = .sample, fakes: FakeRepositories = FakeRepositories()) -> (ResultsModel, FakeRepositories) {
        let env = AppEnvironment.fake(user: user, fakes: fakes)
        return (ResultsModel(env: env, request: request, track: { _ in }, announce: { _ in }), fakes)
    }

    func test_fareCalendarHiddenOn503() async {
        let (model, fakes) = make()
        fakes.agents.onFareCalendar.fails(APIError.server(status: 503, detail: nil))
        let ctx = model.makeContext(layout: .compact)
        guard let load = ctx.fareCalendar else { return XCTFail("signed-in single-city trip offers the calendar") }
        let outcome = await load()
        XCTAssertEqual(outcome, .unavailable)
    }

    func test_otherFailureKeepsServerText() async {
        let (model, fakes) = make()
        fakes.agents.onFareCalendar.fails(APIError.server(status: 500, detail: "Upstream down"))
        let outcome = await model.loadFareCalendar()
        XCTAssertEqual(outcome, .failed("Upstream down"))
    }

    func test_fareCalendarNeedsSignIn() {
        let (model, _) = make(user: nil)
        XCTAssertNil(model.makeContext(layout: .compact).fareCalendar)
    }

    func test_filteredCallsAgentWithFilters() async {
        let (model, fakes) = make()
        fakes.agents.onFiltered.returns(["results": []])
        let ctx = model.makeContext(layout: .compact)
        let outcome = await ctx.filtered?(.hotels, ["max_price_per_night_usd": 200])
        XCTAssertEqual(outcome, .loaded(["results": []]))
        XCTAssertEqual(fakes.agents.onFiltered.lastCall?.section, .hotels)
        XCTAssertEqual(fakes.agents.onFiltered.lastCall?.filters["max_price_per_night_usd"].double, 200)
    }
}
