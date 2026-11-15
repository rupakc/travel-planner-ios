import Foundation

/// `GET|PUT /api/notification-settings`. Called only when `RemoteFeatures.hasNotificationSettings` is true.
public protocol NotificationSettingsRepository: Sendable {
    func get() async throws -> NotificationSettings
    func update(_ patch: NotificationSettingsPatch) async throws -> NotificationSettings
}

/// `GET /api/notifications/catalog`, per locale. Never throws in the live implementation: a failed fetch falls back to
/// the cached catalog of that locale and then to the bundled English one.
public protocol NotificationCatalogRepository: Sendable {
    func templates(locale: AppLanguage) async throws -> NotificationCatalog
}
