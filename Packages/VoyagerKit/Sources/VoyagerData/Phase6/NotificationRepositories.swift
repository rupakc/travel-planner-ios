import Foundation
import Networking
import VoyagerModel

// Notifications 2.0 (`docs/Notifications-API.md`) routes. No coordinates are ever sent to these calls.
extension Endpoints {
    public static func notificationSettings() -> Endpoint<NotificationSettings> {
        Endpoint(path: "/api/notification-settings", telemetryName: "/api/notification-settings")
    }

    public static func updateNotificationSettings(_ patch: NotificationSettingsPatch) -> Endpoint<NotificationSettings> {
        Endpoint(method: .put, path: "/api/notification-settings", telemetryName: "/api/notification-settings", body: patch)
    }

    public static func notificationCatalog(locale: AppLanguage) -> Endpoint<NotificationCatalog> {
        Endpoint(
            path: "/api/notifications/catalog", telemetryName: "/api/notifications/catalog",
            query: [URLQueryItem(name: "locale", value: locale.rawValue)])
    }
}

public struct LiveNotificationSettingsRepository: NotificationSettingsRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func get() async throws -> NotificationSettings { try await api.send(Endpoints.notificationSettings()) }
    public func update(_ patch: NotificationSettingsPatch) async throws -> NotificationSettings {
        try await api.send(Endpoints.updateNotificationSettings(patch))
    }
}

/// The network half of the catalog; `CachedNotificationCatalogRepository` (VoyagerEnv) adds the cache and the fallbacks.
public struct LiveNotificationCatalogRepository: NotificationCatalogRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func templates(locale: AppLanguage) async throws -> NotificationCatalog {
        try await api.send(Endpoints.notificationCatalog(locale: locale))
    }
}

/// The one error code of `Notifications-API.md` that clients translate; everything else keeps the backend `detail`.
public enum NotificationSettingsFailure: String, Error, Sendable, Hashable {
    case invalid = "notification_settings_invalid"

    public static func from(_ error: APIError) -> NotificationSettingsFailure? {
        guard case .client(_, _, let code, let body) = error else { return nil }
        let raw = body["error_code"].string ?? code ?? body["detail"]["error_code"].string
        return raw.flatMap(NotificationSettingsFailure.init(rawValue:))
    }
}
