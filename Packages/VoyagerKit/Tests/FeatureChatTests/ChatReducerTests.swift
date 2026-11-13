import SectionsUI
import TestSupport
import VoyagerModel
import XCTest

@testable import FeatureChat

final class ChatReducerTests: XCTestCase {
    private func run(_ name: String) -> (turn: ChatTurn, effects: [ChatEffect]) {
        var turn = ChatTurn()
        var effects: [ChatEffect] = []
        for json in Fixtures.sse(name) { effects += ChatReducer.reduce(&turn, ChatStreamEvent(json: json)) }
        return (turn, effects)
    }

    func test_qa() {
        let (turn, effects) = run("chat_qa")
        XCTAssertEqual(turn.message.content, "US citizens can visit **Thailand** visa-free for up to 60 days.")
        XCTAssertEqual(turn.message.suggestions, ["Plan a week in Bangkok", "Best time to visit?"])
        XCTAssertEqual(turn.sessionContext?["destination"].string, "Thailand")
        XCTAssertTrue(turn.finished)
        XCTAssertTrue(effects.isEmpty)
    }

    func test_planning() {
        let (turn, effects) = run("chat_planning")
        let planning = turn.message.planning
        XCTAssertEqual(planning?.destination, "Tokyo")
        XCTAssertNotNil(planning?.tripMap)
        XCTAssertEqual(planning?.itinerary?["days"].array?.count, 1)
        XCTAssertEqual(planning?.generating, false)
        XCTAssertEqual(planning?.done, true)
        XCTAssertTrue(turn.message.content.contains("cherry blossom"))
        XCTAssertTrue(turn.finished)
        XCTAssertEqual(effects.filter { $0 == .planningStarted }.count, 1)
    }

    func test_fallback() {
        let (turn, effects) = run("chat_fallback")
        // Only the known section is kept; unknown sections and legacy events are ignored.
        XCTAssertEqual(turn.message.sections.map(\.id), ["hotels"])
        XCTAssertEqual(turn.message.sections.first?.source, .ai)
        XCTAssertTrue(turn.message.loadingAgents.isEmpty)
        XCTAssertEqual(turn.message.importURL, "https://example.com/trip")
        XCTAssertTrue(effects.contains(.openImport("https://example.com/trip")))
        XCTAssertTrue(effects.contains(.planAction(action: "clear", field: "all", data: .null)))
        XCTAssertTrue(effects.contains(.sectionData(section: "hotels", data: Fixtures.sse("chat_fallback")[4]["data"])))
        // `error` with no content shows the generic apology.
        XCTAssertFalse(turn.message.content.isEmpty)
        XCTAssertTrue(turn.message.failed)
        XCTAssertTrue(turn.finished)
    }

    func test_planningDoneTerminates() {
        var turn = ChatTurn()
        _ = ChatReducer.reduce(&turn, .planningStart(destination: "Rome"))
        _ = ChatReducer.reduce(&turn, .itineraryGenerating)
        XCTAssertEqual(turn.message.planning?.generating, true)
        XCTAssertFalse(turn.finished)
        _ = ChatReducer.reduce(&turn, .planningDone)
        XCTAssertTrue(turn.finished)
        XCTAssertEqual(turn.message.planning?.generating, false)
    }

    func test_chipsCapped() {
        var turn = ChatTurn()
        _ = ChatReducer.reduce(&turn, .suggestions(["a", "b", "c", "d", "e", " "]))
        XCTAssertEqual(turn.message.suggestions, ["a", "b", "c", "d"])
    }

    func test_sectionErrorKeepsPriorGoodData() {
        var turn = ChatTurn()
        let good: JSONValue = ["results": [["name": "Park Hyatt"]]]
        _ = ChatReducer.reduce(&turn, .sectionResult(section: "hotels", source: .ai, data: good))
        let effects = ChatReducer.reduce(&turn, .sectionResult(section: "hotels", source: .ai, data: ["error": "boom"]))
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(turn.message.sections.first?.data, good)
        XCTAssertEqual(turn.message.sections.first?.failed, false)
    }

    func test_sectionErrorAloneIsFailed() {
        var turn = ChatTurn()
        _ = ChatReducer.reduce(&turn, .sectionResult(section: "visa", source: nil, data: ["error": "x"]))
        XCTAssertEqual(turn.message.sections.first?.failed, true)
    }

    func test_itineraryErrorShown() {
        var turn = ChatTurn()
        _ = ChatReducer.reduce(&turn, .comprehensiveItinerary(["error": "no plan"]))
        XCTAssertEqual(turn.message.planning?.itineraryError, "no plan")
        XCTAssertNil(turn.message.planning?.itinerary)
    }

    func test_streamEndWithNothingSaysNoResponse() {
        var turn = ChatTurn()
        ChatReducer.finish(&turn)
        XCTAssertTrue(turn.finished)
        XCTAssertFalse(turn.message.content.isEmpty)
    }

    func test_emptyContentNeverSent() {
        var planning = ChatMessageState(role: .assistant, planning: PlanningState(destination: "Tokyo", itinerary: ["days": [[:], [:]]]))
        planning.content = ""
        let blank = ChatMessageState(role: .assistant)
        let messages = [
            ChatMessageState(role: .assistant, content: "welcome"),
            ChatMessageState(role: .user, content: "plan Tokyo"), planning,
            ChatMessageState(role: .user, content: "   "), blank,
            ChatMessageState(role: .user, content: "thanks"),
        ]
        let sent = ChatHistory.requestMessages(messages)
        XCTAssertEqual(sent.map(\.role), ["user", "assistant", "user"])
        XCTAssertTrue(sent.allSatisfy { !$0.content.isEmpty })
        XCTAssertTrue(sent[1].content.contains("Tokyo"))
    }

    func test_messageJSONRoundTrip() {
        let (turn, _) = run("chat_planning")
        var message = turn.message
        message.suggestions = ["x"]
        let back = ChatMessageState(json: message.json)
        XCTAssertEqual(back?.content, message.content)
        XCTAssertEqual(back?.planning?.itinerary, message.planning?.itinerary)
        XCTAssertEqual(back?.suggestions, ["x"])
        XCTAssertNil(ChatMessageState(json: ["role": "robot"]))
    }

    func test_nights() {
        XCTAssertEqual(ChatTelemetry.nights("2026-04-01", "2026-04-08"), 7)
        XCTAssertEqual(ChatTelemetry.nights(nil, "2026-04-08"), 0)
        XCTAssertEqual(ChatTelemetry.nights("bad", "2026-04-08"), 0)
    }
}
