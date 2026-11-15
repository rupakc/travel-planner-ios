import Foundation
import os
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
public final class FakeNotificationPermission: NotificationPermissionProviding {
    private struct State: Sendable {
        var current: NotificationPermissionState
        var requested = 0
    }

    private let box: OSAllocatedUnfairLock<State>
    private let grantsRequest: Bool

    public init(_ state: NotificationPermissionState = .allowed, grantsRequest: Bool = true) {
        box = OSAllocatedUnfairLock(initialState: State(current: state))
        self.grantsRequest = grantsRequest
    }

    public var requestCount: Int { box.withLock { $0.requested } }

    public func state() async -> NotificationPermissionState { box.withLock { $0.current } }

    public func request() async -> Bool {
        let grants = grantsRequest
        box.withLock { value in
            value.requested += 1
            value.current = grants ? .allowed : .denied
        }
        return grants
    }
}
