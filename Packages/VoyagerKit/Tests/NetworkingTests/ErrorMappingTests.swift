import Foundation
import Testing
import VoyagerModel
@testable import Networking

struct ErrorMappingTests {
    private func map(_ status: Int, _ json: String, headers: [String: String] = [:]) -> APIError {
        ErrorMapping.map(status: status, body: Data(json.utf8), headers: headers)
    }

    @Test func test_stringDetail() {
        #expect(map(404, #"{"detail":"Plan not found"}"#) == .notFound("Plan not found"))
        #expect(map(403, #"{"detail":"Admins only"}"#) == .forbidden("Admins only"))
        #expect(map(502, #"{"detail":"upstream"}"#) == .server(status: 502, detail: "upstream"))
        #expect(map(401, "{}") == .unauthorized)
    }

    @Test func test_listDetailHasNoUserFacingText() {
        let error = map(422, #"{"detail":[{"loc":["body","origin"],"msg":"field required","type":"missing"}]}"#)
        guard case .client(let status, let detail, let code, let body) = error else {
            Issue.record("expected .client, got \(error)")
            return
        }
        #expect(status == 422)
        #expect(detail == nil)
        #expect(code == nil)
        #expect(body["detail"][0]["msg"].string == "field required")
        #expect(error.userFacingDetail == nil)
    }

    @Test func test_objectDetailGivesCodeAndMessage() {
        let error = map(422, #"{"detail":{"code":"no_live_price","message":"No live price for this trip"}}"#)
        #expect(error.userFacingDetail == "No live price for this trip")
        guard case .client(_, _, let code, _) = error else {
            Issue.record("expected .client, got \(error)")
            return
        }
        #expect(code == "no_live_price")
    }

    @Test func test_429KeepsBackendStringAndRetryAfter() {
        let error = map(429, #"{"detail":"Too many searches. Try again in 7 minutes."}"#, headers: ["retry-after": "42"])
        #expect(error == .rateLimited(message: "Too many searches. Try again in 7 minutes.", retryAfter: 42))
        #expect(error.userFacingDetail == "Too many searches. Try again in 7 minutes.")
        #expect(map(429, "{}") == .rateLimited(message: "", retryAfter: nil))
    }

    @Test func test_htmlErrorBodyNeverLeaks() {
        let error = ErrorMapping.map(status: 500, body: Data("<html><body>Oops</body></html>".utf8), headers: [:])
        #expect(error == .server(status: 500, detail: nil))
        #expect(error.userFacingDetail == nil)
    }

    @Test func test_clientSideErrorsCarryNoText() {
        for error in [APIError.network, .interrupted, .decoding, .notConfigured, .cancelled, .unauthorized] {
            #expect(error.userFacingDetail == nil)
        }
    }

    @Test func test_htmlOK200IsDecoding() async throws {
        struct Thing: Decodable, Sendable { let id: Int }
        let stub = StubServer { _ in .init(status: 200, headers: ["Content-Type": "text/html"], body: Data("<html>Wi-Fi login</html>".utf8)) }
        let env = ServerEnvironment(buildBaseURL: stub.baseURL, trustedHosts: [], allowsOverride: false, defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let client = APIClient(server: env, tokens: FakeTokens(token: nil), session: stub.session())
        await #expect(throws: APIError.decoding) {
            _ = try await client.send(Endpoint<Thing>(path: "/api/thing", auth: .none))
        }
    }
}
