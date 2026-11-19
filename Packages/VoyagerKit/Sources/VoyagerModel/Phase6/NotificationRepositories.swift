import Foundation

/// `GET|PUT /api/notification-settings`. Called only when `RemoteFeatures.hasNotificationSettings` is true.
public protocol NotificationSettingsRepository: Sendable {
    func get() async throws -> NotificationSettings
    func update(_ patch: NotificationSettingsPatch) async throws -> NotificationSettings
}

/// `GET /api/notifications/catalog`, per locale. A failed fetch falls back to the cached catalog of that locale; with nothing
/// cached it gives the bundled English one for English and throws for any other language.
public protocol NotificationCatalogRepository: Sendable {
    func templates(locale: AppLanguage) async throws -> NotificationCatalog
}
