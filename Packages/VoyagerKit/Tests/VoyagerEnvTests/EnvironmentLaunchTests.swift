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
        #expect(Set(harness.files.reads) == [CurrentPlanStore.fileName, ChatThreadStore.path(for: User.sample.username)])
        #expect(harness.env.chatThreads.username == User.sample.username)
        #expect(harness.recorder.bootstraps.count == 1)
    }

    @Test func test_chatThreadsFollowTheUser() async throws {
        let harness = LiveHarness(session: .sample(token: "tok")) { _ in .init(status: 404, json: "{}") }
        await harness.env.startDeferredWork().value
        #expect(harness.env.chatThreads.username == "amy")
        await harness.env.auth.signOut()
        #expect(await waitUntilOnMain { harness.env.chatThreads.username == nil })
    }

    @Test func test_buildConfigFromBundle() {
        let empty = AppBuildConfig.fromBundle(.main, arguments: [], isDebug: true)
        #expect(empty.baseURL == nil || empty.baseURL?.scheme != nil)
        let overridden = AppBuildConfig.fromBundle(
            .main, arguments: ["app", "-VoyagerBaseURL", "http://127.0.0.1:9000"], isDebug: true)
        #expect(overridden.baseURL == URL(string: "http://127.0.0.1:9000"))
        let release = AppBuildConfig.fromBundle(
            .main, arguments: ["app", "-VoyagerBaseURL", "http://127.0.0.1:9000"], isDebug: false)
        #expect(release.baseURL != URL(string: "http://127.0.0.1:9000"))
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
