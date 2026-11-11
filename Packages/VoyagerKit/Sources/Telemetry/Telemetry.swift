import Foundation
import os
import VoyagerModel

public struct TelemetryBootstrap: Sendable {
    public var appVersion: String
    public var locale: @Sendable () -> String
    /// Base URL + `/api/telemetry`; `nil` while there is no base URL.
    public var endpoint: @Sendable () -> URL?
    public var token: @Sendable () async -> String?
    /// `nil` means `/api/config` was 404 or failed: telemetry is off for the process.
    public var remote: TelemetryRemoteConfig?
    public var storeDirectory: URL
    public var now: @Sendable () -> Date
    public var timeZone: @Sendable () -> TimeZone
    public var transport: TelemetryTransport

    public init(
        appVersion: String,
        locale: @escaping @Sendable () -> String,
        endpoint: @escaping @Sendable () -> URL?,
        token: @escaping @Sendable () async -> String?,
        remote: TelemetryRemoteConfig?,
        storeDirectory: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        transport: TelemetryTransport = URLSessionTelemetryTransport()
    ) {
        self.appVersion = appVersion
        self.locale = locale
        self.endpoint = endpoint
        self.token = token
        self.remote = remote
        self.storeDirectory = storeDirectory
        self.now = now
        self.timeZone = timeZone
        self.transport = transport
    }
}

/// The product telemetry client (docs/Telemetry.md). Every entry point is synchronous and non-throwing for the
/// caller; `track` only appends to an in-memory queue under a lock, and all I/O happens on a private serial
/// `.utility` queue. Call `configure` once at launch; up to 50 events tracked before it are held.
///
/// Emitted internally (do not track these yourself): `app_open` (when collection starts, or when consent is
/// granted later), `app_background` (in `didEnterBackground`), `session_start` (after 30 minutes idle).
public final class Telemetry: Sendable {
    public static let shared = Telemetry()

    /// Events tracked before `configure` (the cold-start metric and the first screen view happen before
    /// `/api/config` has answered) are held, capped, and drained into the queue once telemetry is known
    /// to be on; they are discarded when it is off or consent is missing.
    static let heldCapacity = 50

    private struct State: Sendable {
        var core: TelemetryCore?
        var held: [(event: TelemetryEvent, at: Date)] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public func configure(_ bootstrap: TelemetryBootstrap) {
        configure(bootstrap, defaults: .standard, background: true)
    }

    func configure(_ bootstrap: TelemetryBootstrap, defaults: UserDefaults, background: Bool) {
        let fresh = TelemetryCore(bootstrap, defaults: defaults, background: background)
        let held = state.withLock { state -> [(event: TelemetryEvent, at: Date)] in
            state.core = fresh
            defer { state.held = [] }
            return state.held
        }
        // Not allowed or disabled: `track` rejects them, which discards the held events.
        for item in held { fresh.track(item.event, at: item.at) }
        fresh.start()
    }

    /// Non-blocking, never throws, O(1).
    public func track(_ event: TelemetryEvent) {
        accept(event)
    }

    /// `true` when the event was queued or held for `configure`.
    @discardableResult
    func accept(_ event: TelemetryEvent) -> Bool {
        let now = Date()
        let outcome: (core: TelemetryCore?, held: Bool) = state.withLock { state in
            if let core = state.core { return (core, false) }
            guard state.held.count < Self.heldCapacity else { return (nil, false) }
            state.held.append((event, now))
            return (nil, true)
        }
        if let core = outcome.core { return core.track(event) }
        return outcome.held
    }

    var core: TelemetryCore? { state.withLock { $0.core } }
    var heldCount: Int { state.withLock { $0.held.count } }

    public func setConsent(_ granted: Bool) {
        if let active = core {
            active.setConsent(granted)
        } else {
            Consent.store(granted ? .granted : .denied, in: .standard)
        }
    }

    public var consentChoice: ConsentChoice? { Consent.stored(.standard) }

    public var requiresConsentPrompt: Bool {
        let zone = core?.zoneIdentifier ?? TimeZone.current.identifier
        return consentChoice == nil && Consent.required(timeZone: zone)
    }

    /// Foreground to background: emits `app_background`, flushes with the token, persists the remainder.
    public func didEnterBackground() async {
        await core?.didEnterBackground()
    }

    /// Background-task entry: claims the persisted queue and sends it.
    public func flushPersisted() async {
        await core?.flushPersisted()
    }
}
