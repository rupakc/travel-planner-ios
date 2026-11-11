import AuthCore
import Foundation
import L10n
import os
import Telemetry
import TestSupport
import VoyagerEnv

/// Records the telemetry bootstraps the environment configures.
final class BootstrapRecorder: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [TelemetryBootstrap]())
    var bootstraps: [TelemetryBootstrap] { state.withLock { $0 } }
    func record(_ bootstrap: TelemetryBootstrap) { state.withLock { $0.append(bootstrap) } }
}

/// `AppEnvironment.live` over a stub backend, in-memory files and Keychain, and a private defaults suite.
@MainActor
struct LiveHarness {
    let stub: StubServer
    let files = MemoryFileStore()
    let sessions: InMemorySessionStore
    let recorder = BootstrapRecorder()
    let transport = RecordingTelemetryTransport()
    let env: AppEnvironment

    init(trustedHosts: Set<String> = [], session: Session? = nil, _ handler: @escaping StubServer.Handler) {
        stub = StubServer(handler)
        sessions = InMemorySessionStore(session)
        let defaults = UserDefaults(suiteName: "env-tests-\(UUID().uuidString)") ?? .standard
        let build = AppBuildConfig(baseURL: stub.baseURL, trustedHosts: trustedHosts, appVersion: "1.2.3", isDebug: false)
        let recorder = recorder
        env = AppEnvironment.live(build: build, dependencies: AppEnvironment.LiveDependencies(
            defaults: defaults,
            sessionStore: sessions,
            urlSessionConfiguration: stub.configuration(),
            files: files,
            telemetry: Telemetry(),
            telemetrySetup: TelemetrySetup(
                storeDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                transport: transport),
            language: LanguageController(defaults: defaults, preferred: ["en"]),
            configureTelemetry: { recorder.record($0) }))
    }

    var configRequests: Int { stub.requests.filter { $0.url?.path == "/api/config" }.count }
}
