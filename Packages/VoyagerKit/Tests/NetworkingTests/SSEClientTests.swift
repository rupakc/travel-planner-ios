import Foundation
import os
import Testing
import TestFixtures
import VoyagerModel
@testable import Networking

struct SSEClientTests {
    struct Body: Encodable, Sendable { var origin = "NYC" }

    private func makeClient(
        _ stub: StubServer, tokens: FakeTokens = FakeTokens(token: "tok"),
        hook: (@Sendable () -> Void)? = nil
    ) throws -> SSEClient {
        let env = ServerEnvironment(
            buildBaseURL: stub.baseURL, trustedHosts: [], allowsOverride: false,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )
        return SSEClient(server: env, tokens: tokens, configuration: stub.configuration(), observer: nil, parseHook: hook)
    }

    private func fixtureStub(_ name: String = "sse/search_full.sse") throws -> StubServer {
        let data = try Fixtures.data(name)
        return StubServer { _ in
            var reply = StubServer.Reply(status: 200, headers: ["Content-Type": "text/event-stream"])
            reply.chunks = chunked(data, size: 7)
            return reply
        }
    }

    @Test func test_streamsAllEvents() async throws {
        let stub = try fixtureStub()
        let client = try makeClient(stub)
        var events: [JSONValue] = []
        for try await event in client.stream(path: "/api/search", body: Body(), auth: .optional) { events.append(event) }
        let expected = try Fixtures.sseDataLines("sse/search_full.sse")
        #expect(events.count == expected.count)
        #expect(events.first?["type"].string == "visa")
        #expect(events.last?["type"].string == "done")
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(try JSONDecoder().decode(JSONValue.self, from: try #require(stub.bodies.first))["origin"].string == "NYC")
    }

    @Test func test_interruptedFixtureFinishesNormallyWithoutDone() async throws {
        let client = try makeClient(try fixtureStub("sse/search_interrupted.sse"))
        var events: [JSONValue] = []
        for try await event in client.stream(path: "/api/search", body: Body(), auth: .optional) { events.append(event) }
        #expect(!events.isEmpty)
        #expect(!events.contains { $0["type"].string == "done" })
    }

    @Test func test_http429BeforeStreamMapsRateLimited() async throws {
        let stub = StubServer { _ in .init(status: 429, json: #"{"detail":"Too many searches"}"#, headers: ["Retry-After": "42"]) }
        let client = try makeClient(stub)
        await #expect(throws: APIError.rateLimited(message: "Too many searches", retryAfter: 42)) {
            for try await _ in client.stream(path: "/api/search", body: Body(), auth: .optional) {}
        }
    }

    @Test func test_unauthorizedRetriesOnceThenStreams() async throws {
        let stub = StubServer { request in
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" else {
                return .init(status: 401, json: #"{"detail":"expired"}"#)
            }
            var reply = StubServer.Reply(status: 200, headers: ["Content-Type": "text/event-stream"])
            reply.chunks = [Data("data: {\"type\":\"done\"}\n\n".utf8)]
            return reply
        }
        let client = try makeClient(stub, tokens: FakeTokens(token: "old", refreshesTo: "fresh"))
        var events: [JSONValue] = []
        for try await event in client.stream(path: "/api/chat", body: Body(), auth: .optional) { events.append(event) }
        #expect(events.count == 1)
        #expect(stub.requests.count == 2)
    }

    @Test func test_htmlResponseIsDecodingError() async throws {
        let stub = StubServer { _ in .init(status: 200, headers: ["Content-Type": "text/html"], body: Data("<html>login</html>".utf8)) }
        let client = try makeClient(stub)
        await #expect(throws: APIError.decoding) {
            for try await _ in client.stream(path: "/api/search", body: Body(), auth: .optional) {}
        }
    }

    @Test func test_malformedEventIsSkipped() async throws {
        let stub = StubServer { _ in
            var reply = StubServer.Reply(status: 200, headers: ["Content-Type": "text/event-stream"])
            reply.chunks = [Data("data: not json\n\ndata: {\"type\":\"done\"}\n\n".utf8)]
            return reply
        }
        let client = try makeClient(stub)
        var events: [JSONValue] = []
        for try await event in client.stream(path: "/api/search", body: Body(), auth: .optional) { events.append(event) }
        #expect(events.map { $0["type"].string } == ["done"])
    }

    @Test func test_cancellationStopsTask() async throws {
        let stub = StubServer { _ in
            var reply = StubServer.Reply(status: 200, headers: ["Content-Type": "text/event-stream"])
            reply.endless = Data("data: {\"type\":\"tick\"}\n\n".utf8)
            reply.chunkDelay = 0.01
            return reply
        }
        let client = try makeClient(stub)
        let received = OSAllocatedUnfairLock(initialState: 0)
        let consumer = Task {
            for try await _ in client.stream(path: "/api/search", body: Body(), auth: .optional) {
                received.withLock { $0 += 1 }
            }
        }
        #expect(await waitUntil { received.withLock { $0 } > 0 })
        consumer.cancel()
        #expect(await waitUntil { stub.stopCount >= 1 })
    }

    @Test func test_parsingNotOnMainThread() async throws {
        let onMain = OSAllocatedUnfairLock(initialState: [Bool]())
        let client = try makeClient(try fixtureStub()) { onMain.withLock { $0.append(Thread.isMainThread) } }
        for try await _ in client.stream(path: "/api/search", body: Body(), auth: .optional) {}
        let seen = onMain.withLock { $0 }
        #expect(!seen.isEmpty)
        #expect(!seen.contains(true))
    }
}
