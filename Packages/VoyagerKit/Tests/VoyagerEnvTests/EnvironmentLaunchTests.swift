import AuthCore
import Foundation
import Telemetry
import Testing
import TestSupport
@testable import VoyagerEnv
import VoyagerModel

@MainActor
@Suite struct EnvironmentLaunchTests {
    /// The performance budget: nothing but first-frame work before the first frame. Building the live
    /// environment sends no request and reads no file; `startDeferredWork()` then does both.
    @Test func test_liveInitDoesNoIO() async throws {
        let harness = LiveHarness(session: .sample(token: "tok")) { _ in .init(json: "{}") }
        // Give anything that might have been started a chance to run.
        try await Task.sleep(for: .milliseconds(200))
        #expect(harness.stub.requests.isEmpty)
        #expect(harness.files.reads.isEmpty)
        #expect(harness.files.writes.isEmpty)
        #expect(harness.recorder.bootstraps.isEmpty)
        // The only read is the session (the auth gate needs it for the first frame).
        #expect(harness.sessions.loadCount == 1)
        #expect(harness.env.auth.phase == .signedIn)

        await harness.env.startDeferredWork().value
        #expect(harness.configRequests == 1)
        #expect(harness.stub.requests.count == 1)
        #expect(Set(harness.files.reads) == [CurrentPlanStore.path(for: User.sample.username), ChatThreadStore.path(for: User.sample.username)])
        #expect(harness.env.chatThreads.username == User.sample.username)
        #expect(harness.recorder.bootstraps.count == 1)
    }

    /// First frame never waits on the network: with `/api/config` stalled for good (headers sent, body never
    /// finishes), the environment is built and signed in at once, the main actor keeps running, and
    /// `startDeferredWork()` hands back a still-running task that nothing on the launch path awaits.
    @Test func test_stalledConfigNeverBlocksFirstFrame() async throws {
        var stalled = StubServer.Reply(json: "{")
        stalled.chunks = []
        stalled.endless = Data(" ".utf8)
        stalled.chunkDelay = 0.05
        let reply = stalled
        let harness = LiveHarness(session: .sample(token: "tok")) { _ in reply }
        let started = ContinuousClock.now
        #expect(harness.env.auth.phase == .signedIn)
        let task = harness.env.startDeferredWork()
        // The main actor is free: this sleep and the checks after it complete while the request hangs.
        try await Task.sleep(for: .milliseconds(300))
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(harness.env.auth.phase == .signedIn)
        #expect(harness.recorder.bootstraps.isEmpty, "telemetry waits for the config; it never gates the UI")
        task.cancel()
    }

    @Test func test_chatThreadsFollowTheUser() async throws {
        let harness = LiveHarness(session: .sample(token: "tok")) { _ in .init(status: 404, json: "{}") }
        await harness.env.startDeferredWork().value
        #expect(harness.env.chatThreads.username == "amy")
        await harness.env.auth.signOut()
        #expect(await waitUntilOnMain { harness.env.chatThreads.username == nil })
    }

    @Test func test_buildConfigFromBundle() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "test.bundle", "CFBundleShortVersionString": "4.5.6",
            "VoyagerBaseURL": "https://prod.example.org", "VoyagerTrustedHosts": "Prod.Example.org  other.example.org",
        ]
        try (plist as NSDictionary).write(to: directory.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: directory))
        let prod = URL(string: "https://prod.example.org")
        let override = URL(string: "http://127.0.0.1:9000")

        let plain = AppBuildConfig.fromBundle(bundle, arguments: [], isDebug: true)
        #expect(plain.baseURL == prod)
        #expect(plain.trustedHosts == ["prod.example.org", "other.example.org"])
        #expect(plain.appVersion == "4.5.6")
        let args = ["app", "-VoyagerBaseURL", "http://127.0.0.1:9000"]
        #expect(AppBuildConfig.fromBundle(bundle, arguments: args, isDebug: true).baseURL == override)
        #expect(AppBuildConfig.fromBundle(bundle, arguments: args, isDebug: false).baseURL == prod)
        #expect(AppBuildConfig.fromBundle(bundle, arguments: ["app", "-VoyagerBaseURL"], isDebug: true).baseURL == prod)
        #expect(AppBuildConfig.url("$(VOYAGER_PROD_BASE_URL)") == nil)
        #expect(AppBuildConfig.url("") == nil)
    }

    @Test func test_telemetryGlueCapsAt20() {
        let glue = TelemetryGlue(telemetry: Telemetry())
        for _ in 0..<25 { glue.didFail(endpoint: "/api/plans/:id", status: 500) }
        #expect(glue.reportedCount == 20)
    }

    @Test func test_fakeEnvironmentIsSignedInAndOnboarded() async throws {
        let fakes = FakeRepositories()
        fakes.plans.onList.returns([PlanSummary(id: 3, name: "Kyoto")])
        let env = AppEnvironment.fake(fakes: fakes)
        #expect(env.auth.phase == .signedIn)
        #expect(env.device.onboardingCompleted)
        #expect(try await env.repos.plans.list().map(\.id) == [3])
        #expect(fakes.plans.onList.callCount == 1)
        env.router.open(.myPlan)
        #expect(env.recordedRoutes == [.myPlan])
        #expect(AppEnvironment.fake(user: nil).auth.phase == .signedOut(reason: nil))
        await env.startDeferredWork().value
        #expect(env.clientConfig == nil)
        #expect(fakes.health.onClientConfig.callCount == 1)
    }
}
