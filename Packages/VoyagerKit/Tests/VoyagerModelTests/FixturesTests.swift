import Foundation
import Testing
import TestFixtures

/// Proves the shared fixture directory resolves from `#filePath` (also on the simulator).
@Suite struct FixturesTests {
    @Test func test_sseFixturesResolve() throws {
        for name in ["search_full", "search_interrupted", "chat_qa", "chat_planning", "chat_fallback"] {
            let lines = try Fixtures.sseDataLines("sse/\(name).sse")
            #expect(!lines.isEmpty, "\(name) has data lines")
            #expect(lines.allSatisfy { $0.hasPrefix("{") })
        }
    }

    @Test func test_doneIsLastEventOfFullSearch() throws {
        let lines = try Fixtures.sseDataLines("sse/search_full.sse")
        #expect(lines.last?.contains(#""done""#) == true)
    }

    @Test func test_missingFixtureThrows() {
        #expect(throws: (any Error).self) { try Fixtures.data("nope/missing.json") }
    }
}

