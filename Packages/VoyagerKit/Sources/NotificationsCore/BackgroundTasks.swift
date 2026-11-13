import BackgroundTasks
import Foundation
import UserNotifications
import VoyagerEnv
import VoyagerModel

/// Background refresh: the alert poll (earliest in 30 min, jittered by 5 min) and the telemetry flush (1 h).
/// `register` runs before launch finishes (the app delegate); `schedule` after each trip to the background.
public enum BackgroundTasks {
    public static let alertPollID = "io.github.rupakc.travelplanner.alert-poll"
    public static let telemetryID = "io.github.rupakc.travelplanner.telemetry"

    /// The poller of this launch (so a 404 stops it until the next launch).
    private static let pollerBox = PollerBox()

    @MainActor
    public static func register(env: AppEnvironment) {
        NotificationTapDelegate.install(env: env)
        registerHandlers(env: env)
    }

    /// Nonisolated on purpose: the launch handlers run on a background queue.
    private nonisolated static func registerHandlers(env: AppEnvironment) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: alertPollID, using: nil) { task in
            handle(task, next: schedule) { await pollAlerts(env: env) }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: telemetryID, using: nil) { task in
            handle(task, next: schedule) { await flushTelemetry(env: env) }
        }
    }

    @MainActor
    private static func flushTelemetry(env: AppEnvironment) async {
        await env.telemetry.flushPersisted()
    }

    public static func schedule() {
        submit(alertPollID, earliest: nextAlertPollDate(now: Date(), jitter: .random(in: -300...300)))
        submit(telemetryID, earliest: Date().addingTimeInterval(3600))
    }

    /// 30 minutes from `now`, moved by `jitter` seconds (clamped to +-5 minutes).
    static func nextAlertPollDate(now: Date, jitter: TimeInterval) -> Date {
        now.addingTimeInterval(1800 + min(max(jitter, -300), 300))
    }

    private static func submit(_ id: String, earliest: Date) {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = earliest
        // Throws on the simulator and when background refresh is off: nothing to do about either.
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func pollAlerts(env: AppEnvironment) async {
        guard env.device.alertPoll, env.auth.phase == .signedIn, let user = env.auth.session?.user.username else { return }
        let poller = pollerBox.poller(for: env.repos.notifications, userID: user)
        await poller.poll()
    }

    private static func handle(
        _ task: BGTask,
        next: @escaping @Sendable () -> Void,
        work: @escaping @Sendable () async -> Void
    ) {
        next()
        let box = TaskBox(task)
        let job = Task {
            await work()
            box.complete(true)
        }
        task.expirationHandler = {
            job.cancel()
            box.complete(false)
        }
    }
}

private final class TaskBox: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var done = false
    init(_ task: BGTask) { self.task = task }

    func complete(_ success: Bool) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { task.setTaskCompleted(success: success) }
    }
}

private final class PollerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: AlertPoller?

    /// A new user gets a new poller (its own seen ids, a clean 404 flag).
    func poller(for repo: any NotificationsRepository, userID: String) -> AlertPoller {
        lock.lock()
        defer { lock.unlock() }
        if let current, current.userID == userID { return current }
        let made = AlertPoller(repo: repo, userID: userID)
        current = made
        return made
    }
}

/// Shows notifications while the app is open and routes a tap through the app's router.
@MainActor
final class NotificationTapDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var env: AppEnvironment?
    private static var retained: NotificationTapDelegate?

    static func install(env: AppEnvironment) {
        let delegate = NotificationTapDelegate()
        delegate.env = env
        retained = delegate
        UNUserNotificationCenter.current().delegate = delegate
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = NotificationRouting.route(userInfo: response.notification.request.content.userInfo)
        await MainActor.run { env?.router.open(route) }
    }
}
