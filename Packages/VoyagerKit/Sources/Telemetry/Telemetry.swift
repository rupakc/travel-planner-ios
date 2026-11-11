import Foundation
import os
import VoyagerModel

/// What `GET /api/config` says about telemetry (`telemetry.enabled`, `flush_interval_s`, `max_batch`).
public struct TelemetryRemoteConfig: Sendable, Equatable {
    public var enabled: Bool
    public var flushIntervalS: Int
    public var maxBatch: Int

    public init(enabled: Bool = true, flushIntervalS: Int = 15, maxBatch: Int = 50) {
        self.enabled = enabled
        self.flushIntervalS = flushIntervalS
        self.maxBatch = maxBatch
    }
}

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
/// `.utility` queue. Call `configure` once at launch; events tracked before it are dropped.
///
/// Emitted internally (do not track these yourself): `app_open` (when collection starts, or when consent is
/// granted later), `app_background` (in `didEnterBackground`), `session_start` (after 30 minutes idle).
public final class Telemetry: Sendable {
    public static let shared = Telemetry()

    private let core = OSAllocatedUnfairLock<TelemetryCore?>(initialState: nil)

    public init() {}

    public func configure(_ bootstrap: TelemetryBootstrap) {
        let fresh = TelemetryCore(bootstrap, defaults: .standard, background: true)
        core.withLock { $0 = fresh }
        fresh.start()
    }

    /// Non-blocking, never throws, O(1).
    public func track(_ event: TelemetryEvent) {
        core.withLock { $0 }?.track(event)
    }

    public func setConsent(_ granted: Bool) {
        if let active = core.withLock({ $0 }) {
            active.setConsent(granted)
        } else {
            Consent.store(granted ? .granted : .denied, in: .standard)
        }
    }

    public var consentChoice: ConsentChoice? { Consent.stored(.standard) }

    public var requiresConsentPrompt: Bool {
        let zone = core.withLock { $0 }?.zoneIdentifier ?? TimeZone.current.identifier
        return consentChoice == nil && Consent.required(timeZone: zone)
    }

    /// Foreground to background: emits `app_background`, flushes with the token, persists the remainder.
    public func didEnterBackground() async {
        await core.withLock { $0 }?.didEnterBackground()
    }

    /// Background-task entry: claims the persisted queue and sends it.
    public func flushPersisted() async {
        await core.withLock { $0 }?.flushPersisted()
    }
}
