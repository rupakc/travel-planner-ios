import Foundation
import Networking
import Testing
import TestFixtures
import VoyagerModel
@testable import VoyagerData

struct LiveSearchRepositoryTests {
    private func sseHarness(_ fixture: String, language: AppLanguage = .de) throws -> Harness {
        let data = try Fixtures.data(fixture)
        return try Harness(language: language) { _ in
            var reply = StubServer.Reply(status: 200, headers: ["Content-Type": "text/event-stream"])
            reply.chunks = chunked(data, size: 64)
            return reply
        }
    }

    @Test func test_fixtureToEvents() async throws {
        let h = try sseHarness("sse/search_full.sse")
        let repo = LiveSearchRepository(sse: h.sse, locale: h.locale)
        var events: [SearchStreamEvent] = []
        for try await event in repo.stream(TravelSearchRequest(origin: "NYC", destination: "Tokyo")) { events.append(event) }
        #expect(events.count == (try Fixtures.sseDataLines("sse/search_full.sse")).count)
        guard case .section(let type, let source, _) = events.first else {
            Issue.record("first event is not a section")
            return
        }
        #expect(type == "visa")
        #expect(source == .static)
        #expect(events.last == .done)
        #expect(events.contains(.unknown("future_event_type")), "an unknown type is kept, not fatal")
        #expect(h.request?.url?.path == "/api/search")
        #expect(h.request?.httpMethod == "POST")
    }

    @Test func test_localeInjectedUnlessSet() async throws {
        let h = try sseHarness("sse/search_full.sse")
        let repo = LiveSearchRepository(sse: h.sse, locale: h.locale)
        for try await _ in repo.stream(TravelSearchRequest(destination: "Tokyo")) {}
        for try await _ in repo.stream(TravelSearchRequest(destination: "Tokyo", locale: .fr)) {}
        let locales = Set([try h.body(0)["locale"].string, try h.body(1)["locale"].string])
        #expect(locales == ["de", "fr"])
    }

    @Test func test_anonymousSearchSendsNoToken() async throws {
        let anon = try Harness(token: nil) { _ in .init(status: 200, headers: ["Content-Type": "text/event-stream"]) }
        for try await _ in LiveSearchRepository(sse: anon.sse, locale: anon.locale).stream(TravelSearchRequest()) {}
        #expect(anon.request?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func test_interruptedStreamEndsWithoutDoneAndDoesNotRetry() async throws {
        let h = try sseHarness("sse/search_interrupted.sse")
        let repo = LiveSearchRepository(sse: h.sse, locale: h.locale)
        var events: [SearchStreamEvent] = []
        for try await event in repo.stream(TravelSearchRequest()) { events.append(event) }
        #expect(!events.isEmpty)
        #expect(!events.contains(.done))
        #expect(h.stub.requests.count == 1)
    }

    @Test func test_httpErrorThrows() async throws {
        let h = try Harness { _ in .init(status: 429, json: #"{"detail":"Slow down"}"#) }
        let repo = LiveSearchRepository(sse: h.sse, locale: h.locale)
        await #expect(throws: APIError.rateLimited(message: "Slow down", retryAfter: nil)) {
            for try await _ in repo.stream(TravelSearchRequest()) {}
        }
    }
}
