import AppShell
import UIKit

/// Registers the background tasks before launch finishes (iOS requires it). Their identifiers are in the
/// Info.plist (`BGTaskSchedulerPermittedIdentifiers`, from `project.yml`).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        LiveEnvironment.registerBackgroundTasks()
        return true
    }
}
