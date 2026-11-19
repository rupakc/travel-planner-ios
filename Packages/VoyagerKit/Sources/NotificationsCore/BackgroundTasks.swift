import BackgroundTasks
import Foundation
import Telemetry
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
    public static func pollAlerts(env: AppEnvironment) async {
        guard env.device.alertPoll, env.auth.phase == .signedIn, let user = env.auth.session?.user.username else { return }
        let poller = pollerBox.poller(for: env.repos.notifications, userID: user) { [env] in
            await pollContext(env: env)
        }
        await poller.poll()
    }

    /// The rules for this poll (R9). Nil: the notification settings exist but could not be read, so the poll waits.
    @MainActor
    static func pollContext(env: AppEnvironment) async -> PollContext? {
        let features = RemoteFeatures(config: env.clientConfig)
        // Quiz rows carry game wording: shown unless the server said the account hides the game (`403 game_hidden`).
        let showsGame = StaticGameVisibility.playDriven(
            gameFeature: features.game, hideGameSetting: env.play.hideGameSetting(), hiddenByServer: env.play.isHiddenByServer
        ).showsGame
        guard features.hasNotificationSettings else { return assemble(features: features, showsGame: showsGame, settings: nil, prefs: nil) }
        guard let settings = try? await env.repos.notificationSettings.get() else { return nil }
        NotificationPolicyCache.shared.store(settings)
        var prefs: AlertPrefs?
        if features.hasAlertsV2 { prefs = try? await env.repos.alertsV2.prefs() }
        return assemble(features: features, showsGame: showsGame, settings: settings, prefs: prefs)
    }

    /// The poll rules from what was read. With the v2 alert routes on, unreadable prefs (`prefs` nil) mean the poll
    /// waits (nil): polling without them would skip quiet hours, `instant = targets_only` and the per-kind caps.
    static func assemble(
        features: RemoteFeatures, showsGame: Bool, settings: NotificationSettings?, prefs: AlertPrefs?
    ) -> PollContext? {
        guard features.hasNotificationSettings, let settings else {
            return PollContext(showsGame: showsGame, localTripReminders: true)
        }
        if features.hasAlertsV2 && prefs == nil { return nil }
        let serverPushLive = features.serverPushLive && settings.devices >= 1
        return PollContext(
            settings: settings, prefs: prefs, showsGame: showsGame,
            serverPushLive: serverPushLive, localTripReminders: !serverPushLive)
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
    func poller(
        for repo: any NotificationsRepository, userID: String, context: @escaping @Sendable () async -> PollContext?
    ) -> AlertPoller {
        lock.lock()
        defer { lock.unlock() }
        if let current, current.userID == userID { return current }
        let made = AlertPoller(repo: repo, userID: userID, context: context)
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
        let info = notification.request.content.userInfo
        let push = PushPayload(userInfo: info)
        await MainActor.run { self.recordPush(push) }
        // Foreground presentation honours the category switch (the last settings this launch read).
        if let category = push.category, !NotificationPolicyCache.shared.isEnabled(category) { return [] }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        let info = UserInfoBox(request.content.userInfo)
        let push = PushPayload(userInfo: info.value)
        let isPush = request.trigger is UNPushNotificationTrigger
        await handleTap(info: info, push: push, isPush: isPush)
    }

    /// A cold-launch tap arrives before `/config` has loaded, and the Today and Play flags come from it: wait for the
    /// deferred start (the same task the root view starts) before choosing the route.
    private func handleTap(info: UserInfoBox, push: PushPayload, isPush: Bool) async {
        recordPush(push)
        guard let env else { return }
        await env.startDeferredWork().value
        let route = NotificationRouting.route(
            userInfo: info.value, todayAvailable: env.clientConfig?.journeyAvailable ?? false,
            playAvailable: env.play.isAvailable)
        if let category = Self.openedCategory(info: info.value, push: push) {
            env.telemetry.track(.notifOpen(category: category.rawValue, source: isPush ? "push" : "inapp"))
        }
        env.router.open(route)
    }

    /// The category of the tapped notification: the push's own, or the one its local `route` stands for.
    static func openedCategory(info: [AnyHashable: Any], push: PushPayload) -> NotificationCategory? {
        if let category = push.category { return category }
        switch info["route"] as? String {
        case "trip": return .tripReminders
        case "alerts": return .priceDrops
        case "nearby": return .nearby
        default: return nil
        }
    }

    private func recordPush(_ push: PushPayload) {
        guard let id = push.notificationID, let user = env?.auth.session?.user.username else { return }
        AlertPoller.recordPush(id: id, userID: user)
    }
}

/// A notification's `userInfo` carried into the main actor. It is a plain property list read once and never changed.
private struct UserInfoBox: @unchecked Sendable {
    let value: [AnyHashable: Any]
    init(_ value: [AnyHashable: Any]) { self.value = value }
}

/// The last notification settings this launch read, for the foreground banner decision (no network in `willPresent`).
final class NotificationPolicyCache: @unchecked Sendable {
    static let shared = NotificationPolicyCache()
    private let lock = NSLock()
    private var settings: NotificationSettings?

    func store(_ value: NotificationSettings) {
        lock.lock()
        settings = value
        lock.unlock()
    }

    /// Unknown settings (not read yet) count as on: the server already applied the switches before it sent the push.
    func isEnabled(_ category: NotificationCategory) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return settings?.isEnabled(category) ?? true
    }
}
