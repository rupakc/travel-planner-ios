import AuthCore
import DesignSystem
import Foundation
import L10n
import Networking
import os
import Telemetry
import VoyagerEnv
import VoyagerModel

extension AppEnvironment {
    /// An environment over fakes: `user` is signed in (nil = signed out), onboarding is completed, every
    /// repository is a fake from `fakes` (script it before or in `configure`), files live in memory, settings in
    /// a private `UserDefaults` suite, the router records routes, telemetry is a private, never-configured
    /// instance, and `startDeferredWork()` asks `fakes.health` for the config (nil by default).
    ///
    ///     let fakes = FakeRepositories()
    ///     fakes.plans.onList.returns([...])
    ///     let env = AppEnvironment.fake(fakes: fakes)
    ///     ... fakes.plans.onCreate.calls
    @MainActor
    public static func fake(
        user: User? = .sample,
        fakes: FakeRepositories = FakeRepositories(),
        configure: (inout FakeRepositories) -> Void = { _ in }
    ) -> AppEnvironment {
        var fakes = fakes
        configure(&fakes)
        let defaults = FakeDefaults.make()
        let build = AppBuildConfig(
            baseURL: FakeDefaults.baseURL, trustedHosts: [FakeDefaults.host], appVersion: "0.0.0-test", isDebug: true)
        let server = ServerEnvironment(
            buildBaseURL: build.baseURL, trustedHosts: build.trustedHosts, allowsOverride: false, defaults: defaults)
        let auth = AuthState(api: fakes.auth, store: InMemorySessionStore(user.map { Session.sample(user: $0) }))
        let device = DeviceSettings(defaults: defaults)
        device.onboardingCompleted = true
        let files = MemoryFileStore()
        return AppEnvironment(
            build: build,
            server: server,
            auth: auth,
            providers: AuthProviderCatalog(api: fakes.auth),
            repos: fakes.repositories,
            plan: CurrentPlanStore(files: files),
            chatThreads: ChatThreadStore(files: files),
            device: device,
            theme: ThemeController(defaults: defaults),
            language: LanguageController(defaults: defaults, preferred: ["en"]),
            telemetry: Telemetry(),
            router: RecordingRouter(),
            telemetrySetup: TelemetrySetup(
                storeDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("telemetry-\(UUID().uuidString)"),
                transport: RecordingTelemetryTransport()),
            configureTelemetry: { _ in })
    }

    /// The routes opened so far, when the router is the fake's `RecordingRouter`.
    public var recordedRoutes: [Route] { (router as? RecordingRouter)?.opened ?? [] }
}

enum FakeDefaults {
    static let host = "fake.voyager.test"
    static let baseURL = URL(string: "https://fake.voyager.test")

    /// A fresh, private `UserDefaults` suite (so tests never share settings).
    static func make() -> UserDefaults {
        UserDefaults(suiteName: "voyager-fake-\(UUID().uuidString)") ?? .standard
    }
}

/// Records every `open(_:)`.
@MainActor
public final class RecordingRouter: AppRouting {
    public private(set) var opened: [Route] = []

    public init() {}

    public func open(_ route: Route) { opened.append(route) }
}

/// A `FileStore` in memory that counts reads and writes.
public final class MemoryFileStore: FileStore {
    private struct State: Sendable {
        var files: [String: Data] = [:]
        var reads: [String] = []
        var writes: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(files: [String: Data] = [:]) {
        state.withLock { $0.files = files }
    }

    public var files: [String: Data] { state.withLock { $0.files } }
    /// The paths read, in order (a read of a missing file counts).
    public var reads: [String] { state.withLock { $0.reads } }
    public var writes: [String] { state.withLock { $0.writes } }

    public func read(_ path: String) async throws -> Data? {
        state.withLock { state in
            state.reads.append(path)
            return state.files[path]
        }
    }

    public func write(_ data: Data, to path: String) async throws {
        state.withLock { state in
            state.writes.append(path)
            state.files[path] = data
        }
    }

    public func remove(_ path: String) async throws {
        _ = state.withLock { $0.files.removeValue(forKey: path) }
    }
}

/// A telemetry transport that records posts and answers `outcome`.
public final class RecordingTelemetryTransport: TelemetryTransport {
    public struct Post: Sendable, Equatable {
        public let url: URL
        public let body: Data
        public let gzipped: Bool
        public let token: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: [Post]())
    private let outcome: TransportOutcome

    public init(outcome: TransportOutcome = .ok) { self.outcome = outcome }

    public var posts: [Post] { state.withLock { $0 } }

    public func post(_ url: URL, body: Data, gzipped: Bool, token: String?) async -> TransportOutcome {
        state.withLock { $0.append(Post(url: url, body: body, gzipped: gzipped, token: token)) }
        return outcome
    }
}
