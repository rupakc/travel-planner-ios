import DesignSystem
import NotificationsCore
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
            // A language switch rebuilds the screens so every `L10n` string is read again.
            .id(env.language.language)
            .tint(SemanticColor.primary)
            .preferredColorScheme(env.theme.colorScheme)
            .environment(\.locale, env.language.locale)
            .router(router)
            .onAppear {
                ColdStart.markFirstFrame()
                Task(priority: .utility) { env.startDeferredWork() }
                Task(priority: .utility) { await TripReminderScheduler.refresh(env: env) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { Lifecycle.didEnterBackground(env: env) }
                if phase == .active { Task(priority: .utility) { await TripReminderScheduler.refresh(env: env) } }
            }
            .onOpenURL(perform: open)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { open(url) }
            }
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
    @State private var consent = ConsentState()

    var body: some View {
        AdaptiveColumns {
            TabShell(env: env, router: router, unread: unread, consent: consent)
        } regular: {
            SidebarShell(env: env, router: router, unread: unread, consent: consent)
        }
        .modifier(MyPlanPresentation(env: env, router: router))
        .sheet(isPresented: mainBinding(get: { router.nearbyPresented }, set: { router.nearbyPresented = $0 })) {
            NavigationStack { NearbySheet(env: env) }
        }
        .appShortcuts(router)
        .onChange(of: consent.answered) { _, _ in env.consentAnswerCount += 1 }
        .onChange(of: env.consentPromptRequested) { _, requested in
            guard requested else { return }
            consent.reopen()
            env.consentPromptRequested = false
        }
        .task(id: scenePhase == .active && env.device.alertPoll) {
            // Polled every 60 s while active (and while Settings allows it); cancelled and restarted on a change.
            if scenePhase == .active, env.device.alertPoll { await unread.poll(env.repos.notifications) }
        }
    }
}
