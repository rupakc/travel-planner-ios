import AuthCore
import Foundation
import L10n
import Telemetry
import VoyagerModel

/// Loads `GET /api/config` once per launch. A 404 (older backend) or any failure means "everything off":
/// `nil`, one request, no retry.
public struct ClientConfigLoader: Sendable {
    private let health: any HealthRepository

    public init(health: any HealthRepository) { self.health = health }

    public func load() async -> ClientConfig? {
        do {
            return try await health.clientConfig()
        } catch {
            return nil
        }
    }

    /// The telemetry bootstrap for a loaded (or missing) config. `remote` is nil when the config is
    /// missing, which keeps telemetry off for the process.
    public static func telemetryBootstrap(
        config: ClientConfig?,
        appVersion: String,
        baseURL: @escaping @Sendable () -> URL?,
        token: @escaping @Sendable () async -> String?,
        setup: TelemetrySetup
    ) -> TelemetryBootstrap {
        TelemetryBootstrap(
            appVersion: appVersion,
            locale: { LanguageController.current.rawValue },
            endpoint: { baseURL()?.appendingPathComponent("api/telemetry") },
            token: token,
            remote: config?.telemetry,
            storeDirectory: setup.storeDirectory,
            transport: setup.transport)
    }
}

/// Where telemetry keeps its queue and how it sends.
public struct TelemetrySetup: Sendable {
    public var storeDirectory: URL
    public var transport: any TelemetryTransport

    public init(storeDirectory: URL, transport: any TelemetryTransport = URLSessionTelemetryTransport()) {
        self.storeDirectory = storeDirectory
        self.transport = transport
    }

    /// `Application Support/telemetry` with the URLSession transport. Computing it does no I/O.
    public static func standard() -> TelemetrySetup {
        TelemetrySetup(storeDirectory: URL.applicationSupportDirectory.appendingPathComponent("telemetry", isDirectory: true))
    }
}

extension AccountCapabilities {
    /// The account capabilities `/api/config` advertises in `features`; all off without a config (ruling R7).
    public static func from(config: ClientConfig?) -> AccountCapabilities {
        from(features: config?.features)
    }
}
