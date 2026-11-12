import L10n
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// Compact width: a tab bar, each tab with its own `NavigationStack` path.
struct TabShell: View {
    let env: AppEnvironment
    let router: AppRouter
    let unread: UnreadBadge

    var body: some View {
        TabView(selection: mainBinding(get: { router.selectedTab }, set: { router.selectedTab = $0 })) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                NavigationStack(path: router.binding(for: tab)) {
                    TabRoot(env: env, router: router, tab: tab)
                        .navigationDestination(for: Route.self) { route in
                            RouteDestination(env: env, router: router, route: route)
                        }
                }
                .tabItem { Label(TabInfo.title(tab), systemImage: TabInfo.icon(tab)) }
                .badge(tab == .alerts ? unread.count : 0)
                .tag(tab)
            }
        }
    }
}
