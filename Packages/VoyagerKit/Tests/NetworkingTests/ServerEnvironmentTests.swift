import Foundation
import Testing
@testable import Networking

struct ServerEnvironmentTests {
    private func defaults() throws -> UserDefaults { try #require(UserDefaults(suiteName: UUID().uuidString)) }
    private func url(_ text: String) throws -> URL { try #require(URL(string: text)) }

    @Test func test_adoptRequiresTrustedHttps() throws {
        let build = try url("https://build.example.org")
        let env = ServerEnvironment(buildBaseURL: build, trustedHosts: ["good.example.org"], allowsOverride: false, defaults: try defaults())
        env.adopt(publicBaseURL: try url("http://good.example.org"))
        #expect(env.baseURL == build)
        env.adopt(publicBaseURL: try url("https://evil.example.net"))
        #expect(env.baseURL == build)
        env.adopt(publicBaseURL: try url("https://GOOD.example.org"))
        #expect(env.baseURL?.host?.lowercased() == "good.example.org")
    }

    @Test func test_adoptionPersistsAndIsRevalidated() throws {
        let store = try defaults()
        let first = ServerEnvironment(buildBaseURL: nil, trustedHosts: ["good.example.org"], allowsOverride: false, defaults: store)
        first.adopt(publicBaseURL: try url("https://good.example.org"))
        let second = ServerEnvironment(buildBaseURL: nil, trustedHosts: ["good.example.org"], allowsOverride: false, defaults: store)
        #expect(second.baseURL == (try url("https://good.example.org")))
        let untrusting = ServerEnvironment(buildBaseURL: nil, trustedHosts: [], allowsOverride: false, defaults: store)
        #expect(untrusting.baseURL == nil)
    }

    @Test func test_overrideRejectsPublicHttp() throws {
        let env = ServerEnvironment(buildBaseURL: nil, trustedHosts: [], allowsOverride: true, defaults: try defaults())
        for bad in ["http://example.com", "http://8.8.8.8:8001", "http://172.32.0.1", "http://11.0.0.1", "ftp://localhost"] {
            #expect(throws: ServerEnvironmentError.self, "\(bad)") { try env.setOverride(try url(bad)) }
        }
        for good in ["http://localhost:8001", "http://127.0.0.1:8001", "http://mac.local:8001", "http://10.0.0.5", "http://172.16.4.2", "http://192.168.1.20:8001", "https://example.com"] {
            try env.setOverride(try url(good))
            #expect(env.baseURL == (try url(good)), "\(good)")
        }
        try env.setOverride(nil)
        #expect(env.baseURL == nil)
    }

    @Test func test_overrideNotAllowedInRelease() throws {
        let env = ServerEnvironment(buildBaseURL: nil, trustedHosts: [], allowsOverride: false, defaults: try defaults())
        #expect(throws: ServerEnvironmentError.overrideNotAllowed) { try env.setOverride(try url("http://localhost:8001")) }
    }

    @Test func test_overrideWinsAndPersists() throws {
        let store = try defaults()
        let build = try url("https://build.example.org")
        let env = ServerEnvironment(buildBaseURL: build, trustedHosts: [], allowsOverride: true, defaults: store)
        try env.setOverride(try url("http://localhost:8001"))
        let reloaded = ServerEnvironment(buildBaseURL: build, trustedHosts: [], allowsOverride: true, defaults: store)
        #expect(reloaded.baseURL == (try url("http://localhost:8001")))
        let release = ServerEnvironment(buildBaseURL: build, trustedHosts: [], allowsOverride: false, defaults: store)
        #expect(release.baseURL == build)
    }

    @Test func test_nilBaseURLNotConfigured() async throws {
        let env = ServerEnvironment(buildBaseURL: nil, trustedHosts: [], allowsOverride: false, defaults: try defaults())
        #expect(env.baseURL == nil)
        let client = APIClient(server: env, tokens: FakeTokens(token: "t"))
        await #expect(throws: APIError.notConfigured) {
            _ = try await client.send(Endpoint<Empty>(path: "/api/x"))
        }
        let sse = SSEClient(server: env, tokens: FakeTokens(token: "t"), configuration: .ephemeral)
        await #expect(throws: APIError.notConfigured) {
            for try await _ in sse.stream(path: "/api/search", body: ["q": "x"], auth: .optional) {}
        }
    }
}
