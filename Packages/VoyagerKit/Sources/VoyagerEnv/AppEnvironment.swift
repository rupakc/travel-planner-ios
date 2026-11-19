import AuthCore
import DesignSystem
import Foundation
import L10n
import Networking
import Observation
import os
import Telemetry
import VoyagerData
import VoyagerModel

/// Everything a screen needs, created once at launch (`live`) or per test (`AppEnvironment.fake` in TestSupport).
/// Building it does no network or file I/O: `startDeferredWork()` (after the first frame) loads `/api/config`,
/// configures telemetry, adopts `public_base_url` and restores the current plan and the chat threads.
@MainActor @Observable
public final class AppEnvironment {
    public let build: AppBuildConfig
    public let server: ServerEnvironment
    public let auth: AuthState
    public let providers: AuthProviderCatalog
    public let repos: Repositories
    public let plan: CurrentPlanStore
    public let chatThreads: ChatThreadStore
    public let device: DeviceSettings
    public let theme: ThemeController
    public let language: LanguageController
    public let telemetry: Telemetry
    /// AppShell installs its router; until then `open` does nothing.
    public var router: any AppRouting
    /// Settings sets it ("Privacy choices"); the shell shows the consent card again and clears it.
    public var consentPromptRequested = false
    /// Bumped each time the consent card is answered, so Settings re-reads the choice.
    public var consentAnswerCount = 0
    /// `GET /api/config`; nil until it loaded, and for good on an older backend (404) or a failure.
    public private(set) var clientConfig: ClientConfig?
    public private(set) var capabilities: AccountCapabilities

    @ObservationIgnored private let telemetrySetup: TelemetrySetup
    @ObservationIgnored private let configureTelemetry: @Sendable (TelemetryBootstrap) -> Void
    @ObservationIgnored private var deferredTask: Task<Void, Never>?
    @ObservationIgnored private var configFailures = 0
    @ObservationIgnored private var configRetrying = false
    @ObservationIgnored private var nextConfigRetry = Date.distantPast
    @ObservationIgnored private var watchCoordinator: WatchCreateCoordinator?
    @ObservationIgnored private var alertsV2Service: AlertsV2Service?
    @ObservationIgnored private var sharesService: SharesService?
    @ObservationIgnored private var socialService: SocialService?
    @ObservationIgnored private var playService: PlayService?
    /// The user whose chat threads are shown (`.none` = not loaded yet; `.some(nil)` = signed out).
    @ObservationIgnored private var chatUser: String??

    /// The one seam every watch create / change / delete goes through (`WatchCreateCoordinator`, the Alerts tab). The app
    /// shell sets it to refresh local reminders and poll for alerts; unset (tests, previews) it does nothing.
    @ObservationIgnored public var onWatchesChanged: (@MainActor () async -> Void)?

    /// Call after a watch was created, changed or deleted on the server.
    public func watchesChanged(removed: (kind: WatchKind, id: Int)? = nil) async {
        watchCoordinator?.watchesDidChange(removed: removed)
        await onWatchesChanged?()
    }

    /// Serves "Watch price" taps from Results and Chat (created on first use: it refers back to the environment).
    public var watches: WatchCreateCoordinator {
        if let watchCoordinator { return watchCoordinator }
        let coordinator = WatchCreateCoordinator(env: self)
        watchCoordinator = coordinator
        return coordinator
    }

    /// The Phase 3 (price alerts 2.0) routes behind their feature flags.
    public var alertsV2: AlertsV2Service {
        if let alertsV2Service { return alertsV2Service }
        let service = AlertsV2Service(env: self)
        alertsV2Service = service
        return service
    }

    /// Where downloaded share cards live (temporary storage). Tests point it at their own directory before first use.
    @ObservationIgnored public var shareCardStore: ShareCardStore = .standard

    /// The Phase 4 (share links 2.0) routes behind `features.sharing`, and the temporary card store.
    public var shares: SharesService {
        if let sharesService { return sharesService }
        let service = SharesService(env: self, cards: shareCardStore)
        sharesService = service
        return service
    }

    /// The Phase 5 social routes behind `features.social`.
    public var social: SocialService {
        if let socialService { return socialService }
        let service = SocialService(env: self)
        socialService = service
        return service
    }

    /// The Phase 5 Play routes behind `features.play` and the hidden game.
    public var play: PlayService {
        if let playService { return playService }
        let service = PlayService(env: self)
        playService = service
        return service
    }

    /// `configureTelemetry` defaults to `telemetry.configure`; tests pass a recorder.
    public init(
        build: AppBuildConfig,
        server: ServerEnvironment,
        auth: AuthState,
        providers: AuthProviderCatalog,
        repos: Repositories,
        plan: CurrentPlanStore,
        chatThreads: ChatThreadStore,
        device: DeviceSettings,
        theme: ThemeController,
        language: LanguageController,
        telemetry: Telemetry,
        router: any AppRouting = UnroutedRouter(),
        clientConfig: ClientConfig? = nil,
        telemetrySetup: TelemetrySetup = .standard(),
        configureTelemetry: (@Sendable (TelemetryBootstrap) -> Void)? = nil
    ) {
        self.build = build
        self.server = server
        self.auth = auth
        self.providers = providers
        self.repos = repos
        self.plan = plan
        self.chatThreads = chatThreads
        self.device = device
        self.theme = theme
        self.language = language
        self.telemetry = telemetry
        self.router = router
        self.clientConfig = clientConfig
        self.capabilities = .from(config: clientConfig)
        self.telemetrySetup = telemetrySetup
        self.configureTelemetry = configureTelemetry ?? { [telemetry] bootstrap in telemetry.configure(bootstrap) }
    }

    // MARK: - Live

    /// What `live` builds on. `standard()` is the app; tests swap the network, the files and the Keychain.
    public struct LiveDependencies {
        public var defaults: UserDefaults
        /// nil = the Keychain.
        public var sessionStore: (any SessionStore)?
        /// For `APIClient` and `SSEClient` (tests add a `URLProtocol`).
        public var urlSessionConfiguration: URLSessionConfiguration
        public var files: any FileStore
        public var telemetry: Telemetry
        public var telemetrySetup: TelemetrySetup
        /// nil = `LanguageController.shared` (the one that drives `L10n`).
        public var language: LanguageController?
        public var configureTelemetry: (@Sendable (TelemetryBootstrap) -> Void)?

        public init(
            defaults: UserDefaults = .standard,
            sessionStore: (any SessionStore)? = nil,
            urlSessionConfiguration: URLSessionConfiguration = .default,
            files: any FileStore = DiskFileStore.applicationSupport(),
            telemetry: Telemetry = .shared,
            telemetrySetup: TelemetrySetup = .standard(),
            language: LanguageController? = nil,
            configureTelemetry: (@Sendable (TelemetryBootstrap) -> Void)? = nil
        ) {
            self.defaults = defaults
            self.sessionStore = sessionStore
            self.urlSessionConfiguration = urlSessionConfiguration
            self.files = files
            self.telemetry = telemetry
            self.telemetrySetup = telemetrySetup
            self.language = language
            self.configureTelemetry = configureTelemetry
        }
    }

    public static func live(build: AppBuildConfig) -> AppEnvironment {
        live(build: build, dependencies: LiveDependencies())
    }

    /// Wires the live graph. No request and no file read happens here (the Keychain read of the session is the
    /// auth gate's first-frame work).
    public static func live(build: AppBuildConfig, dependencies deps: LiveDependencies) -> AppEnvironment {
        let server = ServerEnvironment(
            buildBaseURL: build.baseURL, trustedHosts: build.trustedHosts, allowsOverride: build.isDebug,
            defaults: deps.defaults)
        let glue = TelemetryGlue(telemetry: deps.telemetry)
        // AuthState needs the auth API, whose client needs AuthState's token: the late provider closes the loop.
        let tokens = LateTokenProvider()
        let api = APIClient(
            server: server, tokens: tokens, session: URLSession(configuration: deps.urlSessionConfiguration), observer: glue)
        let sse = SSEClient(server: server, tokens: tokens, configuration: deps.urlSessionConfiguration, observer: glue)
        let authAPI = LiveAuthAPI(api: api)
        let auth = AuthState(api: authAPI, store: deps.sessionStore ?? KeychainSessionStore(defaults: deps.defaults))
        tokens.install(AuthTokenAdapter(auth: auth))
        let language = deps.language ?? LanguageController.shared
        return AppEnvironment(
            build: build,
            server: server,
            auth: auth,
            providers: AuthProviderCatalog(api: authAPI),
            repos: .live(api: api, sse: sse, locale: { LanguageController.current }),
            plan: CurrentPlanStore(files: deps.files),
            chatThreads: ChatThreadStore(files: deps.files),
            device: DeviceSettings(defaults: deps.defaults),
            theme: ThemeController(defaults: deps.defaults),
            language: language,
            telemetry: deps.telemetry,
            telemetrySetup: deps.telemetrySetup,
            configureTelemetry: deps.configureTelemetry)
    }

    // MARK: - After the first frame

    /// Runs once (later calls return the same task): loads `/api/config` (one request; 404 or failure → nil, no
    /// retry), sets the capabilities, adopts a trusted `public_base_url`, configures telemetry (off without a
    /// config), restores the current plan and loads the user's chat threads.
    @discardableResult
    public func startDeferredWork() -> Task<Void, Never> {
        if let deferredTask { return deferredTask }
        let task = Task { [self] in
            let userLoad = observeAuth()
            let fetched = await ClientConfigLoader(health: repos.health).fetch()
            let config = fetched.config
            if fetched.failed {
                // Offline or a server error: stay off for now, and let the next start try again.
                deferredTask = nil
                configFailures = 1
                nextConfigRetry = Date().addingTimeInterval(Self.configRetryDelay(failures: 1))
                await userLoad?.value
                return
            }
            await adopt(config)
            await userLoad?.value
        }
        deferredTask = task
        return task
    }

    /// Waits (at most `limit` seconds) for a deferred start that is already running, and never starts one: a failed
    /// `/config` fetch cleared `deferredTask`, so this returns at once and leaves the retry backoff alone.
    public func awaitDeferredWork(limit: Double = 3) async {
        guard let running = deferredTask else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await running.value }
            group.addTask { try? await Task.sleep(for: .seconds(limit)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func adopt(_ config: ClientConfig?) async {
        apply(config)
        let bootstrap = ClientConfigLoader.telemetryBootstrap(
            config: config, appVersion: build.appVersion,
            baseURL: { [server] in server.baseURL },
            token: { [auth] in auth.tokenSnapshot() },
            setup: telemetrySetup)
        let configure = configureTelemetry
        await Task.detached(priority: .utility) { configure(bootstrap) }.value
    }

    /// Delay before the next config retry after `failures` failed fetches: 30 s doubling to 10 min.
    static func configRetryDelay(failures: Int) -> TimeInterval {
        min(600, 30 * pow(2, Double(max(0, failures - 1))))
    }

    /// Scene foreground (the app has no reachability hook): when a launch-time `/api/config` fetch failed
    /// (offline cold start), tries again, at most once per backoff window and never while one is running.
    /// Does nothing once config is loaded or before the first launch fetch has settled.
    public func refetchConfigIfMissing(now: Date = Date()) async {
        guard clientConfig == nil, configFailures > 0, !configRetrying, now >= nextConfigRetry else { return }
        configRetrying = true
        defer { configRetrying = false }
        let fetched = await ClientConfigLoader(health: repos.health).fetch()
        if fetched.failed {
            configFailures += 1
            nextConfigRetry = now.addingTimeInterval(Self.configRetryDelay(failures: configFailures))
            return
        }
        configFailures = 0
        await adopt(fetched.config)
    }

    /// Writes the current plan and chat threads now (before the app is suspended).
    public func flushPersistence() async {
        await plan.flushPersistence()
        await chatThreads.flushPersistence()
    }

    private func apply(_ config: ClientConfig?) {
        clientConfig = config
        capabilities = .from(config: config)
        if let url = config?.publicBaseURL {
            // Only an https URL on a trusted host is adopted (ServerEnvironment checks).
            server.adopt(publicBaseURL: url)
        }
    }

    /// Follows the signed-in user: their plan and chat threads replace the previous user's.
    @discardableResult
    func observeAuth() -> Task<Void, Never>? {
        let username = withObservationTracking {
            auth.session?.user.username
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeAuth() }
        }
        guard chatUser != .some(username) else { return nil }
        // Launch and every sign-out or user switch: cached share cards are the previous user's.
        shares.cards.purge()
        // The next user starts with whatever `/config` says: a degraded or hidden-game flag was the previous user's.
        social.reset()
        play.reset()
        watchCoordinator?.resetForUserChange()
        chatUser = .some(username)
        let threads = chatThreads
        let plan = plan
        return Task {
            async let planSwitch: Void = plan.switchUser(username)
            await threads.switchUser(username)
            await planSwitch
        }
    }
}

/// The router before AppShell installs its own: navigation requests are dropped (and logged in Debug).
@MainActor
public final class UnroutedRouter: AppRouting {
    private static let log = Logger(subsystem: "io.github.rupakc.travelplanner", category: "router")

    public init() {}

    public func open(_ route: Route) {
        Self.log.debug("No router installed; dropped \(TelemetryRouteName.template(for: route), privacy: .public)")
    }
}

/// An `AccessTokenProvider` installed after construction (breaks the AuthState ↔ APIClient cycle).
final class LateTokenProvider: AccessTokenProvider {
    private let inner = OSAllocatedUnfairLock<AuthTokenAdapter?>(initialState: nil)

    func install(_ provider: AuthTokenAdapter) { inner.withLock { $0 = provider } }

    func currentToken() async -> String? {
        await inner.withLock { $0 }?.currentToken()
    }

    func unauthorized(token: String) async -> Bool {
        await inner.withLock { $0 }?.unauthorized(token: token) ?? false
    }
}
