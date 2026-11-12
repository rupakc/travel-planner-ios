import FeatureAdmin
import FeatureAlerts
import FeatureAuth
import FeatureOnboarding
import FeaturePreferences
import FeatureResults
import FeatureSettings
import FeatureTrips
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

enum TabInfo {
    static func title(_ tab: AppTab) -> String {
        switch tab {
        case .trips: L10n.text(K.mobile.tabs.trips)
        case .explore: L10n.text(K.mobile.tabs.explore)
        case .alerts: L10n.text(K.mobile.tabs.alerts)
        case .you: L10n.text(K.mobile.tabs.you)
        }
    }

    static func icon(_ tab: AppTab) -> String {
        switch tab {
        case .trips: "suitcase"
        case .explore: "safari"
        case .alerts: "bell"
        case .you: "person.crop.circle"
        }
    }

    static func modeTitle(_ mode: ExploreMode) -> String {
        switch mode {
        case .search: L10n.text(K.common.nav.search)
        case .chat: L10n.text(K.common.nav.chat)
        case .compare: L10n.text(K.search.modes.compare)
        case .link: L10n.text(K.search.modes.import)
        case .discover: L10n.text(K.search.modes.discover)
        }
    }

    static func modeIcon(_ mode: ExploreMode) -> String {
        switch mode {
        case .search: "magnifyingglass"
        case .chat: "bubble.left.and.bubble.right"
        case .compare: "square.split.2x1"
        case .link: "link"
        case .discover: "dice"
        }
    }
}

/// The root view of a tab, with its screen telemetry.
struct TabRoot: View {
    let env: AppEnvironment
    let router: AppRouter
    let tab: AppTab
    var showsModePicker = true

    var body: some View {
        switch tab {
        case .trips:
            TripsRootView(env: env).telemetryRoute("/trips").telemetryScreen("/trips")
        case .explore:
            ExploreContainer(env: env, router: router, showsPicker: showsModePicker)
        case .alerts:
            AlertsRootView(env: env, kind: router.alertsFocus?.kind, watchID: router.alertsFocus?.watchID)
                .id(router.alertsFocus)
                .telemetryRoute("/alerts").telemetryScreen("/alerts")
        case .you:
            SettingsRootView(env: env).telemetryRoute("/settings").telemetryScreen("/settings")
        }
    }
}

/// The screen a pushed `Route` opens, with its `screen_view` (the route template, never the ids).
struct RouteDestination: View {
    let env: AppEnvironment
    let router: AppRouter
    let route: Route

    var body: some View {
        let template = TelemetryRouteName.template(for: route)
        content
            .telemetryRoute(template)
            .telemetryScreen(template)
    }

    @ViewBuilder private var content: some View {
        switch route {
        case .results(let request): ResultsView(env: env, request: request)
        case .planDetail(let id): PlanDetailView(env: env, planID: id)
        case .notifications: NotificationsInboxView(env: env)
        case .preferences: PreferencesView(env: env)
        case .tasteProfile: TasteProfileView(env: env)
        case .admin: AdminRootView(env: env)
        case .changePassword(let forced): ChangePasswordView(env: env, forced: forced)
        case .onboarding(let fromSettings):
            OnboardingView(env: env, fromSettings: fromSettings) { _ in
                env.device.onboardingCompleted = true
                router.pop(.you)
            }
        case .alerts(let kind, let watchID): AlertsRootView(env: env, kind: kind, watchID: watchID)
        default: EmptyState(icon: "questionmark.circle", title: TelemetryRouteName.template(for: route))
        }
    }
}
