import Foundation
import UserNotifications
import VoyagerModel

/// The iOS notification permission, read and asked for by Settings. A seam so tests never touch the system.
public protocol NotificationPermissionProviding: Sendable {
    func state() async -> NotificationPermissionState
    /// Shows the system prompt; the answer is whether notifications are now allowed.
    func request() async -> Bool
}

/// The live permission (`UNUserNotificationCenter`).
public struct SystemNotificationPermission: NotificationPermissionProviding {
    public init() {}

    public func state() async -> NotificationPermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    public func request() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}
