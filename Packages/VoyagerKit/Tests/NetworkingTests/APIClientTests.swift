import Foundation
import Testing
import VoyagerModel
@testable import Networking

struct APIClientTests {
    struct Plan: Codable, Sendable, Equatable { let id: Int; let name: String }

    private func makeClient(
        _ stub: StubServer, tokens: FakeTokens, observer: RecordingObserver? = nil
    ) throws -> APIClient {
        let env = ServerEnvironment(
            buildBaseURL: stub.baseURL, trustedHosts: [], allowsOverride: false,
            defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )
        return APIClient(server: env, tokens: tokens, session: stub.session(), observer: observer)
    }

    @Test func test_bearerAddedWhenRequired() async throws {
        let stub = StubServer { _ in .init(json: #"{"id":1,"name":"Tokyo"}"#) }
        let client = try makeClient(stub, tokens: FakeTokens(token: "abc"))
        let plan = try await client.send(Endpoint<Plan>(path: "/api/plans/1", query: [URLQueryItem(name: "a", value: "x+y")]))
        #expect(plan == Plan(id: 1, name: "Tokyo"))
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(request.url?.path == "/api/plans/1")
        #expect(request.url?.query == "a=x%2By")
        #expect(request.httpMethod == "GET")
    }

    @Test func test_requiredWithoutTokenMakesNoRequest() async throws {
        let stub = StubServer()
        let client = try makeClient(stub, tokens: FakeTokens(token: nil))
        await #expect(throws: APIError.unauthorized) { _ = try await client.send(Endpoint<Empty>(path: "/api/plans")) }
        #expect(stub.requests.isEmpty)
    }

    @Test func test_optionalAuthWithoutToken() async throws {
        let stub = StubServer { _ in .init(json: #"{"id":2,"name":"Rome"}"#) }
        let client = try makeClient(stub, tokens: FakeTokens(token: nil))
        _ = try await client.send(Endpoint<Plan>(path: "/api/x", auth: .optional))
        #expect(try #require(stub.requests.first).value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func test_authNoneNeverSendsToken() async throws {
        let stub = StubServer { _ in .init(json: #"{"id":2,"name":"Rome"}"#) }
        let client = try makeClient(stub, tokens: FakeTokens(token: "abc"))
        _ = try await client.send(Endpoint<Plan>(path: "/api/x", auth: .none))
        #expect(try #require(stub.requests.first).value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func test_postBodyEncodedAsJSON() async throws {
        let stub = StubServer { _ in .init(json: #"{"id":3,"name":"Oslo"}"#) }
        let client = try makeClient(stub, tokens: FakeTokens(token: "abc"))
        _ = try await client.send(Endpoint<Plan>(method: .post, path: "/api/plans", body: Plan(id: 0, name: "Oslo")))
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let sent = try JSONDecoder().decode(Plan.self, from: try #require(stub.bodies.first))
        #expect(sent == Plan(id: 0, name: "Oslo"))
    }

    @Test func test_timeoutClasses() {
        #expect(TimeoutClass.standard.seconds == 30)
        #expect(TimeoutClass.ai.seconds == 300)
    }

    @Test func test_unauthorizedRetriesOnceWhenProviderRefreshes() async throws {
        let stub = StubServer { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh"
                ? .init(json: #"{"id":1,"name":"Tokyo"}"#)
                : .init(status: 401, json: #"{"detail":"expired"}"#)
        }
        let tokens = FakeTokens(token: "old", refreshesTo: "fresh")
        let client = try makeClient(stub, tokens: tokens)
        let plan = try await client.send(Endpoint<Plan>(path: "/api/plans/1"))
        #expect(plan.id == 1)
        #expect(stub.requests.count == 2)
        #expect(tokens.unauthorizedTokens == ["old"])
    }

    @Test func test_secondUnauthorizedDoesNotLoop() async throws {
        let stub = StubServer { _ in .init(status: 401, json: #"{"detail":"nope"}"#) }
        let client = try makeClient(stub, tokens: FakeTokens(token: "old", refreshesTo: "fresh"))
        await #expect(throws: APIError.unauthorized) { _ = try await client.send(Endpoint<Empty>(path: "/api/plans")) }
        #expect(stub.requests.count == 2)
    }

    @Test func test_staleUnauthorizedIgnored() async throws {
        let stub = StubServer { _ in .init(status: 401, json: #"{"detail":"expired"}"#) }
        let tokens = FakeTokens(token: "stale", refreshesTo: nil)
        let client = try makeClient(stub, tokens: tokens)
        await #expect(throws: APIError.unauthorized) { _ = try await client.send(Endpoint<Empty>(path: "/api/plans")) }
        #expect(stub.requests.count == 1)
        #expect(tokens.unauthorizedTokens == ["stale"])
    }

    @Test func test_anonymous401DoesNotTouchTokenProvider() async throws {
        let stub = StubServer { _ in .init(status: 401, json: "{}") }
        let tokens = FakeTokens(token: nil)
        let client = try makeClient(stub, tokens: tokens)
        await #expect(throws: APIError.unauthorized) { _ = try await client.send(Endpoint<Empty>(path: "/api/x", auth: .optional)) }
        #expect(tokens.unauthorizedTokens.isEmpty)
    }

    @Test func test_404ConfigIsNotFound() async throws {
        let stub = StubServer { _ in .init(status: 404, json: #"{"detail":"Not Found"}"#) }
        let client = try makeClient(stub, tokens: FakeTokens(token: nil))
        await #expect(throws: APIError.notFound("Not Found")) {
            _ = try await client.raw(Endpoint<JSONValue>(path: "/api/config", auth: .none))
        }
    }

    @Test func test_emptyResponseFor204() async throws {
        let stub = StubServer { _ in .init(status: 204) }
        let client = try makeClient(stub, tokens: FakeTokens(token: "t"))
        let result = try await client.send(Endpoint<Empty>(method: .delete, path: "/api/plans/9"))
        #expect(result == Empty())
    }

    @Test func test_rawReturnsHeaders() async throws {
        let stub = StubServer { _ in .init(json: #"{"ok":true}"#, headers: ["X-Thing": "1"]) }
        let client = try makeClient(stub, tokens: FakeTokens(token: "t"))
        let (json, response) = try await client.raw(Endpoint<JSONValue>(path: "/api/x"))
        #expect(json["ok"].bool == true)
        #expect(response.value(forHTTPHeaderField: "X-Thing") == "1")
    }

    @Test func test_observerGetsTemplateNotPath() async throws {
        let stub = StubServer { _ in .init(status: 500, json: #"{"detail":"boom"}"#) }
        let observer = RecordingObserver()
        let client = try makeClient(stub, tokens: FakeTokens(token: "t"), observer: observer)
        await #expect(throws: APIError.server(status: 500, detail: "boom")) {
            _ = try await client.send(Endpoint<Empty>(path: "/api/plans/42", telemetryName: "/api/plans/:id"))
        }
        #expect(observer.recorded == ["500 /api/plans/:id"])
        #expect(!observer.recorded.contains { $0.contains("42") })
    }

    @Test func test_networkFailureMapsToNetwork() async throws {
        let stub = StubServer()
        let env = ServerEnvironment(
            buildBaseURL: URL(string: "https://unregistered-\(UUID().uuidString.prefix(6).lowercased()).stub"),
            trustedHosts: [], allowsOverride: false, defaults: try #require(UserDefaults(suiteName: UUID().uuidString))
        )
        let observer = RecordingObserver()
        let client = APIClient(server: env, tokens: FakeTokens(token: nil), session: stub.session(), observer: observer)
        await #expect(throws: APIError.network) { _ = try await client.send(Endpoint<Empty>(path: "/api/x", auth: .none)) }
        #expect(observer.recorded == ["0 /api/x"])
    }
}
