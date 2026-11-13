/// Notification permission. `request` is called only from onboarding step 4 or the Settings toggle, never at launch.
public enum NotificationPermission {
    public static func request(center: any NotificationCenterClient = SystemNotificationCenter()) async -> Bool {
        await center.requestAuthorization()
    }

    public static func isGranted(center: any NotificationCenterClient = SystemNotificationCenter()) async -> Bool {
        await center.isAuthorized()
    }
}
