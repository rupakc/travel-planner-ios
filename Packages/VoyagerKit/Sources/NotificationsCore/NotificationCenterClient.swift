import Foundation
import UserNotifications

/// A local notification to show, now (`fireComponents == nil`) or at a calendar time.
public struct LocalNotification: Sendable, Equatable {
    public var id: String
    public var title: String
    public var body: String
    public var fireComponents: DateComponents?
    /// String-only payload read back by `NotificationRouting` when the notification is tapped.
    public var userInfo: [String: String]

    public init(
        id: String,
        title: String,
        body: String,
        fireComponents: DateComponents? = nil,
        userInfo: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.fireComponents = fireComponents
        self.userInfo = userInfo
    }
}

/// The slice of `UNUserNotificationCenter` this module uses, so tests run against a fake.
public protocol NotificationCenterClient: Sendable {
    /// Asks the system for permission (alert, sound, badge); the answer is whether it was granted.
    func requestAuthorization() async -> Bool
    /// Whether notifications may be shown now (authorized or provisional).
    func isAuthorized() async -> Bool
    func add(_ notification: LocalNotification) async
    func pendingIdentifiers() async -> [String]
    func removePending(identifiers: [String]) async
}

/// The live center. `UNUserNotificationCenter` is thread-safe.
public struct SystemNotificationCenter: NotificationCenterClient {
    public init() {}

    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    public func add(_ notification: LocalNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = notification.userInfo
        var trigger: UNNotificationTrigger?
        if let components = notification.fireComponents {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    public func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    public func removePending(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
