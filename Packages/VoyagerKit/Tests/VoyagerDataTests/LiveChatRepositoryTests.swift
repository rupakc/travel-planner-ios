import Foundation
import Networking
import Testing
import TestFixtures
import VoyagerModel
@testable import VoyagerData

struct LiveChatRepositoryTests {
    @Test func test_planningSequence() async throws {
        let data = try Fixtures.data("sse/chat_planning.sse")
        let h = try Harness { _ in
            var reply = StubServer.Reply(status: 200, headers: ["Content-Type": "text/event-stream"])
            reply.chunks = chunked(data, size: 50)
            return reply
        }
        let repo = LiveChatRepository(sse: h.sse, locale: h.locale)
        var events: [ChatStreamEvent] = []
        for try await event in repo.stream(ChatRequest(messages: [ChatMessage(role: "user", content: "Plan Tokyo")])) { events.append(event) }
        let names = events.map { event -> String in
            switch event {
            case .planningStart: "planning_start"
            case .tripMap: "trip_map"
            case .itineraryGenerating: "itinerary_generating"
            case .comprehensiveItinerary: "comprehensive_itinerary"
            case .delta: "delta"
            case .sessionContextUpdate: "session_context_update"
            case .suggestions: "suggestions"
            case .planningDone: "planning_done"
            default: "other"
            }
        }
        #expect(Array(names.prefix(4)) == ["planning_start", "trip_map", "itinerary_generating", "comprehensive_itinerary"])
        #expect(names.last == "planning_done")
        #expect(!names.contains("other"))
        #expect(events.first == .planningStart(destination: "Tokyo"))
        #expect(h.request?.url?.path == "/api/chat")
        #expect(h.request?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let body = try h.body()
        #expect(body["locale"].string == "de")
        #expect(body["messages"][0]["content"].string == "Plan Tokyo")
    }

    @Test func test_signedOutFailsWithoutARequest() async throws {
        let h = try Harness(token: nil)
        let repo = LiveChatRepository(sse: h.sse, locale: h.locale)
        await #expect(throws: APIError.unauthorized) {
            for try await _ in repo.stream(ChatRequest(messages: [])) {}
        }
        #expect(h.stub.requests.isEmpty)
    }
}
