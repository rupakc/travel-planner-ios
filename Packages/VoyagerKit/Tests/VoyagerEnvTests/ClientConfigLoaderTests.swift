import AuthCore
import Foundation
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@MainActor
@Suite struct ClientConfigLoaderTests {
    @Test func test_404DisablesTelemetryAndNoRetry() async throws {
        let harness = LiveHarness { request in
            request.url?.path == "/api/config"
                ? .init(status: 404, json: #"{"detail": "Not Found"}"#)
                : .init(status: 500, json: "{}")
        }
        await harness.env.startDeferredWork().value
        await harness.env.startDeferredWork().value

        #expect(harness.stub.requests.count == 1)
        #expect(harness.configRequests == 1)
        #expect(harness.env.clientConfig == nil)
        #expect(harness.env.capabilities == .none)
        // Telemetry is configured once, with no remote config: off for the process.
        #expect(harness.recorder.bootstraps.count == 1)
        let bootstrap = try #require(harness.recorder.bootstraps.first)
        #expect(bootstrap.remote == nil)
        #expect(bootstrap.appVersion == "1.2.3")
        #expect(harness.transport.posts.isEmpty)
    }

    @Test func test_networkFailureIsNil() async {
        let loader = ClientConfigLoader(health: FailingHealth())
        #expect(await loader.load() == nil)
    }

    @Test func test_adoptsTrustedPublicBaseURL() async throws {
        let body = #"""
        {"public_base_url": "https://voyager.example.org", "telemetry": {"enabled": true, "flush_interval_s": 30},
         "features": {"account_deletion": true, "signup": false}}
        """#
        let harness = LiveHarness(trustedHosts: ["voyager.example.org"]) { _ in .init(json: body) }
        let original = harness.env.server.baseURL
        await harness.env.startDeferredWork().value

        #expect(harness.env.server.baseURL == URL(string: "https://voyager.example.org"))
        #expect(original != harness.env.server.baseURL)
        #expect(harness.env.clientConfig?.telemetry.enabled == true)
        #expect(harness.env.capabilities.deleteAccount)
        #expect(!harness.env.capabilities.signUp)
        let bootstrap = try #require(harness.recorder.bootstraps.first)
        #expect(bootstrap.remote?.enabled == true)
        #expect(bootstrap.remote?.flushIntervalS == 30)
        #expect(bootstrap.endpoint() == URL(string: "https://voyager.example.org/api/telemetry"))
    }

    @Test func test_untrustedPublicBaseURLIgnored() async {
        let harness = LiveHarness(trustedHosts: ["voyager.example.org"]) { _ in
            .init(json: #"{"public_base_url": "https://evil.example.com"}"#)
        }
        let original = harness.env.server.baseURL
        await harness.env.startDeferredWork().value
        #expect(harness.env.clientConfig?.publicBaseURL == URL(string: "https://evil.example.com"))
        #expect(harness.env.server.baseURL == original)
    }

    @Test func test_capabilitiesFromConfig() {
        #expect(AccountCapabilities.from(config: nil) == .none)
        let config = ClientConfig(features: ["password_reset": true, "refresh_tokens": true])
        let capabilities = AccountCapabilities.from(config: config)
        #expect(capabilities.passwordReset && capabilities.refreshTokens)
        #expect(!capabilities.deleteAccount)
    }
}

private struct FailingHealth: HealthRepository {
    struct Offline: Error {}
    func health() async throws -> Health { throw Offline() }
    func clientConfig() async throws -> ClientConfig? { throw Offline() }
}
