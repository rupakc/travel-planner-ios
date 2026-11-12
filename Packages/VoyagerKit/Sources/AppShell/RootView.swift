import DesignSystem
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The window content: the auth gate (login, forced password change, onboarding, shell), the consent card,
/// the theme and language, deep links and the lifecycle hooks.
public struct RootView: View {
    let env: AppEnvironment
    let router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    @MainActor public init(env: AppEnvironment) {
        self.env = env
        // Idempotent: the router is installed once, however often SwiftUI rebuilds this struct.
        if let existing = env.router as? AppRouter {
            router = existing
        } else {
            let installed = AppRouter()
            env.router = installed
            router = installed
        }
    }

    public var body: some View {
        AuthGate(env: env, router: router)
            .overlay(alignment: .bottom) {
                // Never over the login screen's button; the shell is the first screen that can show it.
                if showsConsent { ConsentCard(telemetry: env.telemetry) }
            }
            .tint(SemanticColor.primary)
            .preferredColorScheme(env.theme.colorScheme)
            .environment(\.locale, env.language.locale)
            .router(router)
            .onAppear {
                ColdStart.markFirstFrame()
                Task(priority: .utility) { env.startDeferredWork() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { Lifecycle.didEnterBackground(env: env) }
            }
            .onOpenURL(perform: open)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { open(url) }
            }
    }

    private var showsConsent: Bool {
        GateScreen.screen(
            phase: env.auth.phase, onboardingCompleted: env.device.onboardingCompleted, sharedToken: router.sharedToken
        ) == .shell
    }

    private func open(_ url: URL) {
        if let route = DeepLinks.route(for: url, env: env) { router.open(route) }
    }
}

/// The signed-in shell: tabs (compact) or a sidebar (regular), the My Plan and Near me presentations, the
/// unread-alerts poll and the keyboard shortcuts.
struct ShellView: View {
    let env: AppEnvironment
    let router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var unread = UnreadBadge()

    var body: some View {
        AdaptiveColumns {
            TabShell(env: env, router: router, unread: unread)
        } regular: {
            SidebarShell(env: env, router: router, unread: unread)
        }
        .modifier(MyPlanPresentation(env: env, router: router))
        .sheet(isPresented: mainBinding(get: { router.nearbyPresented }, set: { router.nearbyPresented = $0 })) {
            NavigationStack { NearbySheet(env: env) }
        }
        .appShortcuts(router)
        .task(id: scenePhase == .active) {
            // Polled every 60 s while active; cancelled (and restarted) on a phase change.
            if scenePhase == .active { await unread.poll(env.repos.notifications) }
        }
    }
}
