import SectionsUI
import TestSupport
import VoyagerModel
import XCTest

@testable import FeatureResults

final class ResultsReducerTests: XCTestCase {
    private func section(_ type: String, _ data: JSONValue, source: SectionSource? = .ai) -> SearchStreamEvent {
        .section(type: type, source: source, data: data)
    }

    private func fixtureEvents() -> [SearchStreamEvent] {
        Fixtures.sse("search_full").map(SearchStreamEvent.init(json:))
    }

    func test_initialStatuses() {
        let state = ResultsState()
        XCTAssertEqual(state.sections.count, 17)
        for id in SectionID.allCases {
            let expected: SectionStatus = [.itinerary, .stressTest, .packingList, .facts].contains(id) ? .waiting : .loading
            XCTAssertEqual(state.status(id), expected, id.rawValue)
        }
    }

    func test_staticThenAiReplaces() {
        var state = ResultsState()
        state = ResultsReducer.reduce(state, section("visa", ["requirement": ["visa_type": "static"]], source: .static))
        XCTAssertEqual(state.status(.visa), .enhancing)
        state = ResultsReducer.reduce(state, section("visa", ["requirement": ["visa_type": "ai"]], source: .ai))
        XCTAssertEqual(state.status(.visa), .done)
        XCTAssertEqual(state.data(.visa)?["requirement"]["visa_type"].string, "ai")
    }

    func test_noSourceIsDone() {
        let state = ResultsReducer.reduce(ResultsState(), section("weather", ["days": []], source: nil))
        XCTAssertEqual(state.status(.weather), .done)
    }

    func test_aiErrorKeepsStatic() {
        var state = ResultsState()
        state = ResultsReducer.reduce(state, section("tips", ["tips": [["title": "Carry cash"]]], source: .static))
        state = ResultsReducer.reduce(state, section("tips", ["error": "boom"], source: .ai))
        XCTAssertEqual(state.status(.tips), .done)
        XCTAssertEqual(state.data(.tips)?["tips"][0]["title"].string, "Carry cash")
    }

    func test_aiErrorWithoutDataIsError() {
        let state = ResultsReducer.reduce(ResultsState(), section("hotels", ["error": "no hotels"]))
        XCTAssertEqual(state.status(.hotels), .error("no hotels"))
    }

    func test_repeatReplaces() {
        var state = ResultsState()
        state = ResultsReducer.reduce(state, section("hotels", ["results": [["name": "A"]]]))
        state = ResultsReducer.reduce(state, section("hotels", ["results": [["name": "B"]]]))
        XCTAssertEqual(state.data(.hotels)?["results"].array?.count, 1)
        XCTAssertEqual(state.data(.hotels)?["results"][0]["name"].string, "B")
    }

    func test_itineraryWaitsForActivitiesAndHotels() {
        var state = ResultsState()
        state = ResultsReducer.reduce(state, section("activities", ["results": []]))
        XCTAssertEqual(state.status(.itinerary), .waiting)
        state = ResultsReducer.reduce(state, section("hotels", ["results": []], source: .static))
        XCTAssertEqual(state.status(.itinerary), .loading)
        XCTAssertEqual(state.status(.stressTest), .waiting)
        state = ResultsReducer.reduce(state, section("itinerary", ["days": [["day_number": 1]]], source: nil))
        XCTAssertEqual(state.status(.itinerary), .done)
        XCTAssertEqual(state.status(.stressTest), .loading)
    }

    func test_erroredItineraryStillStartsStressTest() {
        var state = ResultsState()
        state = ResultsReducer.reduce(state, section("itinerary", ["error": "boom"]))
        XCTAssertEqual(state.status(.stressTest), .loading)
    }

    func test_confidenceAndPricingAreNotTiles() {
        var state = ResultsState()
        state = ResultsReducer.reduce(state, section("confidence", ["grade": "green"], source: .static))
        state = ResultsReducer.reduce(state, section("pricing_advisor", ["route": "A"]))
        XCTAssertEqual(state.confidence?["grade"].string, "green")
        XCTAssertEqual(state.pricing?["route"].string, "A")
        XCTAssertEqual(state.sections.count, 17)
    }

    func test_streamEndMarksDone() {
        var state = ResultsState()
        state = ResultsReducer.reduce(state, section("visa", ["requirement": [:]], source: .static))
        state = ResultsReducer.reduce(state, .done)
        XCTAssertTrue(state.done)
        for id in SectionID.allCases { XCTAssertEqual(state.status(id), .done, id.rawValue) }
    }

    // MARK: - Place facts (optional section)

    private static let facts: JSONValue = [
        "places": [[
            "key": "city:1", "scope": "city", "name": "Berlin",
            "groups": ["historical": [["id": "c:1", "text": "Founded in 1237.", "origin": "crawler"]]],
        ]],
    ]

    private static let merged: JSONValue = [
        "places": [[
            "key": "city:1", "scope": "city", "name": "Berlin",
            "groups": [
                "historical": [["id": "c:1", "text": "Founded in 1237.", "origin": "crawler"]],
                "fun": [["id": "a:1", "text": "A currywurst museum.", "origin": "ai"]],
            ],
        ]],
    ]

    func test_factsStayHiddenWithoutFacts() {
        var state = ResultsState()
        XCTAssertFalse(state.visibleSections.contains(.facts))
        state = ResultsReducer.reduce(state, .done)
        XCTAssertNil(state.data(.facts))
        XCTAssertFalse(state.visibleSections.contains(.facts), "an older backend never sends facts")
    }

    func test_crawlerFactsEnhanceThenAiFinishes() {
        var state = ResultsReducer.reduce(ResultsState(), section("facts", Self.facts, source: .crawler))
        XCTAssertEqual(state.status(.facts), .enhancing)
        XCTAssertTrue(state.visibleSections.contains(.facts))
        state = ResultsReducer.reduce(state, section("facts", Self.merged, source: .ai))
        XCTAssertEqual(state.status(.facts), .done)
        XCTAssertEqual(state.data(.facts), Self.merged)
    }

    func test_lateCrawlerFactsNeverReplaceAiFacts() {
        var state = ResultsReducer.reduce(ResultsState(), section("facts", Self.merged, source: .ai))
        state = ResultsReducer.reduce(state, section("facts", Self.facts, source: .crawler))
        XCTAssertEqual(state.status(.facts), .done)
        XCTAssertEqual(state.data(.facts), Self.merged)
    }

    func test_crawlerOnlyFactsAreDoneAtStreamEnd() {
        var state = ResultsReducer.reduce(ResultsState(), section("facts", Self.facts, source: .crawler))
        state = ResultsReducer.reduce(state, .done)
        XCTAssertEqual(state.status(.facts), .done)
        XCTAssertEqual(state.data(.facts), Self.facts)
    }

    func test_factsErrorNeverShowsOrReplacesFacts() {
        var state = ResultsReducer.reduce(ResultsState(), section("facts", ["error": "boom", "error_code": "ai_limit"]))
        XCTAssertEqual(state.status(.facts), .waiting)
        XCTAssertNil(state.banner, "a facts error is never a banner")
        XCTAssertFalse(state.visibleSections.contains(.facts))
        state = ResultsReducer.reduce(state, section("facts", Self.facts, source: .crawler))
        state = ResultsReducer.reduce(state, section("facts", ["error": "no_facts"]))
        state = ResultsReducer.reduce(state, section("facts", ["places": []]))
        XCTAssertEqual(state.data(.facts), Self.facts, "crawler facts stay")
    }

    func test_factsAreNotCountedInProgress() {
        var state = ResultsReducer.reduce(ResultsState(), section("facts", Self.merged))
        XCTAssertEqual(state.completedCount, 0)
        state = ResultsReducer.reduce(state, section("visa", ["requirement": [:]], source: .static))
        XCTAssertEqual(state.completedCount, 1)
        XCTAssertEqual(SectionID.agentOrder.count, 16)
    }

    func test_failedStreamKeepsFactsHiddenOrDone() {
        let empty = ResultsReducer.failed(ResultsState(), message: "Slow down")
        XCTAssertEqual(empty.status(.facts), .waiting)
        XCTAssertFalse(empty.visibleSections.contains(.facts))
        let withFacts = ResultsReducer.failed(
            ResultsReducer.reduce(ResultsState(), section("facts", Self.facts, source: .crawler)), message: "Slow down")
        XCTAssertEqual(withFacts.status(.facts), .done)
    }

    func test_factsEventIsASection() {
        let event = SearchStreamEvent(json: ["type": "facts", "source": "crawler", "data": Self.facts])
        XCTAssertEqual(event, .section(type: "facts", source: .crawler, data: Self.facts))
    }

    func test_unknownIgnored() {
        let before = ResultsState()
        XCTAssertEqual(ResultsReducer.reduce(before, section("future_type", ["x": 1])), before)
        XCTAssertEqual(ResultsReducer.reduce(before, .unknown("zzz")), before)
        XCTAssertEqual(ResultsReducer.reduce(before, .agentStatus(agent: "flights", status: "searching")), before)
    }

    func test_clientItineraryFallbackWhenNoneArrived() {
        let search: JSONValue = ["destination": "Tokyo", "departure_date": "2026-04-01", "return_date": "2026-04-04"]
        var state = ResultsState(searchData: search)
        state = ResultsReducer.reduce(state, section("activities", ["results": [["name": "Tsukiji", "price_usd": 40]]]))
        state = ResultsReducer.reduce(state, section("hotels", ["results": [["name": "Park Hyatt"]]]))
        state = ResultsReducer.reduce(state, .done)
        let days = state.data(.itinerary)?["days"].array
        XCTAssertEqual(days?.count, 4)
        XCTAssertEqual(days?.first?["date"].string, "2026-04-01")
        XCTAssertEqual(days?.last?["date"].string, "2026-04-04")
        XCTAssertEqual(days?[1]["slots"][0]["activity"].string, "Tsukiji")
        XCTAssertEqual(days?[1]["slots"][0]["estimated_cost_usd"].double, 40)
        XCTAssertEqual(state.data(.itinerary)?["source"].string, "template")
        XCTAssertEqual(state.status(.itinerary), .done)
    }

    func test_serverItineraryIsKept() {
        var state = ResultsState(searchData: ["departure_date": "2026-04-01"])
        state = ResultsReducer.reduce(state, section("itinerary", ["days": [["day_number": 1]]], source: nil))
        state = ResultsReducer.reduce(state, .done)
        XCTAssertEqual(state.data(.itinerary)?["days"].array?.count, 1)
    }

    func test_pendingVerificationClearedAtEnd() {
        var state = ResultsState()
        state = ResultsReducer.reduce(state, section("hotels", ["results": [], "verification": ["pending": true, "level": "partial"]]))
        state = ResultsReducer.reduce(state, .done)
        XCTAssertEqual(state.data(.hotels)?["verification"]["pending"].bool, false)
        XCTAssertEqual(state.data(.hotels)?["verification"]["level"].string, "partial")
    }

    func test_aiLimitSetsBanner() {
        let state = ResultsReducer.reduce(
            ResultsState(), section("flights", ["error": "AI limit reached", "error_code": "ai_limit"]))
        XCTAssertEqual(state.banner, "AI limit reached")
    }

    func test_fixtureFullEndsAllDone() {
        let search: JSONValue = ["destination": "Tokyo", "departure_date": "2026-04-01", "return_date": "2026-04-08"]
        let state = fixtureEvents().reduce(ResultsState(searchData: search), ResultsReducer.reduce)
        XCTAssertTrue(state.done)
        for id in SectionID.allCases {
            XCTAssertEqual(state.status(id), .done, id.rawValue)
        }
        XCTAssertNotNil(state.confidence)
        XCTAssertNotNil(state.pricing)
        XCTAssertNotNil(state.data(.itinerary))
        XCTAssertNotNil(state.data(.stressTest))
        XCTAssertNotNil(state.data(.packingList))
    }
}
