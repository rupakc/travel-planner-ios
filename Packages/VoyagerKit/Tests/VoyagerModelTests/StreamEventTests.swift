import Foundation
import Testing
import TestFixtures
@testable import VoyagerModel

@Suite struct StreamEventTests {
    private func json(_ line: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    @Test func test_searchFullHasNoUnknown() throws {
        let events = try Fixtures.sseDataLines("sse/search_full.sse").map { SearchStreamEvent(json: try json($0)) }
        #expect(!events.isEmpty)
        for event in events {
            if case .unknown(let type) = event, type != "future_event_type" { Issue.record("unknown search event \(type)") }
        }
        #expect(events.contains(.unknown("future_event_type")))
        #expect(events.last == .done)
        #expect(events.contains(.agentStatus(agent: "flights", status: "searching")))
    }

    @Test func test_chatPlanningHasNoUnknown() throws {
        let events = try Fixtures.sseDataLines("sse/chat_planning.sse").map { ChatStreamEvent(json: try json($0)) }
        for event in events {
            if case .unknown(let type) = event { Issue.record("unknown chat event \(type)") }
        }
        #expect(events.first == .planningStart(destination: "Tokyo"))
        #expect(events[2] == .itineraryGenerating)
        #expect(events.last == .planningDone)
        #expect(events.contains(.suggestions(["Add a day trip to Nikko"])))
        #expect(events.contains(.delta("Heads up: cherry blossom season is busy.")))
        if case .tripMap(let map) = events[1] { #expect(map["cities"][0]["city"] == "Tokyo") } else { Issue.record("no trip_map") }
        if case .comprehensiveItinerary(let data) = events[3] { #expect(data["trip_summary"]["total_nights"] == 5) } else { Issue.record("no itinerary") }
    }

    @Test func test_chatQaAndFallback() throws {
        let qa = try Fixtures.sseDataLines("sse/chat_qa.sse").map { ChatStreamEvent(json: try json($0)) }
        #expect(qa.last == .done)
        if case .sessionContextUpdate(let context) = qa[3] { #expect(context["destination"] == "Thailand") } else { Issue.record("no context") }
        let fallback = try Fixtures.sseDataLines("sse/chat_fallback.sse").map { ChatStreamEvent(json: try json($0)) }
        #expect(fallback[0] == .planAction(action: "add", field: "activities", data: ["name": "Tsukiji food tour", "price_usd": 120]))
        #expect(fallback.contains(.importLink(url: "https://example.com/trip")))
        #expect(fallback.contains(.error("Sorry, something went wrong.")))
        #expect(fallback.contains(.sectionResult(section: "mystery", source: .ai, data: ["x": 1])))
        #expect(fallback.contains(.unknown("plan_clear")))
    }

    @Test func test_unknownTypeIsUnknown() throws {
        #expect(SearchStreamEvent(json: try json(#"{"type": "hologram"}"#)) == .unknown("hologram"))
        #expect(SearchStreamEvent(json: try json(#"{"no_type": 1}"#)) == .unknown(""))
        #expect(ChatStreamEvent(json: try json(#"{"type": "hologram"}"#)) == .unknown("hologram"))
    }

    @Test func test_sectionSourceStatic() throws {
        let event = SearchStreamEvent(json: try json(#"{"type": "visa", "data": {"requirement": {}}, "source": "static"}"#))
        #expect(event == .section(type: "visa", source: .static, data: ["requirement": [:]]))
        let ai = SearchStreamEvent(json: try json(#"{"type": "visa", "data": {}, "source": "ai"}"#))
        #expect(ai == .section(type: "visa", source: .ai, data: [:]))
        let none = SearchStreamEvent(json: try json(#"{"type": "itinerary", "data": {"days": []}}"#))
        #expect(none == .section(type: "itinerary", source: nil, data: ["days": []]))
    }

    @Test func test_planningDoneAndDoneDistinct() throws {
        let done = ChatStreamEvent(json: try json(#"{"type": "done"}"#))
        let planning = ChatStreamEvent(json: try json(#"{"type": "planning_done"}"#))
        #expect(done == .done)
        #expect(planning == .planningDone)
        #expect(done != planning)
    }
}
