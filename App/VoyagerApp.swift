import AppShell
import SwiftUI

@main
struct VoyagerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let env: AppEnvironment

    /// Registers the bundled fonts and builds the live environment, and nothing else: no I/O happens before the
    /// first frame (`RootView` starts the deferred work after it).
    init() {
        FontRegistry.registerOnce()
        env = LiveEnvironment.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView(env: env)
        }
    }
}
