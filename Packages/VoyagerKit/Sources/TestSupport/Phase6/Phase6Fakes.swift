import Foundation
import VoyagerEnv
import VoyagerModel

/// A scripted `NotificationSettingsRepository`. Unscripted calls throw `FakeRepositoryError.notScripted`.
public final class FakeNotificationSettingsRepository: NotificationSettingsRepository {
    public let onGet = FakeCall<Void, NotificationSettings>("notificationSettings.get") { _ in NotificationSettings() }
    public let onUpdate = FakeCall<NotificationSettingsPatch, NotificationSettings>("notificationSettings.update")
    public init() {}

    public func get() async throws -> NotificationSettings { try await onGet() }
    public func update(_ patch: NotificationSettingsPatch) async throws -> NotificationSettings { try await onUpdate(patch) }
}

/// A scripted `NotificationCatalogRepository`; the default answer is the bundled English catalog.
public final class FakeNotificationCatalogRepository: NotificationCatalogRepository {
    public let onTemplates = FakeCall<AppLanguage, NotificationCatalog>("notificationCatalog.templates") { _ in
        NotificationCatalog.bundledEnglish
    }
    public init() {}

    public func templates(locale: AppLanguage) async throws -> NotificationCatalog { try await onTemplates(locale) }
}

/// A `NotificationPermissionProviding` with a fixed state; `request()` answers `grantsRequest` and moves the state.
public final class FakeNotificationPermission: NotificationPermissionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: NotificationPermissionState
    private var requested = 0
    private let grantsRequest: Bool

    public init(_ state: NotificationPermissionState = .allowed, grantsRequest: Bool = true) {
        current = state
        self.grantsRequest = grantsRequest
    }

    public var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    public func state() async -> NotificationPermissionState {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func request() async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        requested += 1
        current = grantsRequest ? .allowed : .denied
        return grantsRequest
    }
}
