@_exported import DesignSystem
@_exported import VoyagerEnv
import Foundation
import NotificationsCore
import Telemetry
#if canImport(UIKit)
import UIKit
#endif

/// The one live environment of the process. The app delegate (which registers the background tasks before launch
/// finishes) and `VoyagerApp` both reach it here, so their order does not matter. Building it does no I/O.
@MainActor
public enum LiveEnvironment {
    public static let shared = AppEnvironment.live(build: .fromBundle())

    /// `application(_:didFinishLaunchingWithOptions:)`: the identifiers are in the Info.plist
    /// (`BGTaskSchedulerPermittedIdentifiers`).
    public static func registerBackgroundTasks() {
        BackgroundTasks.register(env: shared)
    }
}

/// What happens when the app leaves the foreground.
@MainActor
enum Lifecycle {
    /// Flushes telemetry and persists the plan and chat threads inside a background task, then schedules the
    /// next background refresh. (`Telemetry.didEnterBackground` itself emits `app_background`.)
    static func didEnterBackground(env: AppEnvironment) {
        let box = BackgroundTaskBox()
        #if canImport(UIKit)
        box.identifier = UIApplication.shared.beginBackgroundTask(withName: "voyager.background-flush") { [box] in
            box.end()
        }
        #endif
        let telemetry = env.telemetry
        Task {
            await telemetry.didEnterBackground()
            await env.flushPersistence()
            box.end()
        }
        BackgroundTasks.schedule()
    }
}

/// Ends the UIKit background task exactly once (from the work or from the expiration handler).
@MainActor
final class BackgroundTaskBox {
    #if canImport(UIKit)
    var identifier = UIBackgroundTaskIdentifier.invalid
    #endif

    func end() {
        #if canImport(UIKit)
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
        #endif
    }
}
