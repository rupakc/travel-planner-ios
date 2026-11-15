import Foundation
import Networking
import VoyagerData
import VoyagerModel

/// The one door to the notification-settings routes. It never calls a route whose flag is off (`notifications_api`
/// absent or 0: an older backend keeps today's screens, silently), refuses an invalid patch before the call, and a bare
/// `404 Not Found` from a flagged route (a stale `/config`, cached 5 min) turns the feature off for this service.
@MainActor
public final class NotificationSettingsService {
    /// Thrown instead of calling a route whose flag is off.
    public struct Unavailable: Error, Equatable, Sendable {}

    private unowned let env: AppEnvironment
    private var degraded = false

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var features: RemoteFeatures { RemoteFeatures(config: env.clientConfig) }

    public var isAvailable: Bool { !degraded && features.hasNotificationSettings }

    public func settings() async throws -> NotificationSettings {
        try await run { try await $0.get() }
    }

    /// Answers the full settings object. An invalid patch throws `422 notification_settings_invalid` without a request.
    public func update(_ patch: NotificationSettingsPatch) async throws -> NotificationSettings {
        guard patch.isValid else {
            let code = NotificationSettingsFailure.invalid.rawValue
            throw APIError.client(status: 422, detail: nil, code: code, body: .object(["error_code": .string(code)]))
        }
        return try await run { try await $0.update(patch) }
    }

    private func run<T>(_ operation: (any NotificationSettingsRepository) async throws -> T) async throws -> T {
        guard isAvailable else { throw Unavailable() }
        do {
            return try await operation(env.repos.notificationSettings)
        } catch let error as APIError {
            if AlertsV2Failure.isRouteMissing(error) { degraded = true }
            throw error
        }
    }
}
