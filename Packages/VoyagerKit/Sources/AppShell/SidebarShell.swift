import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

private enum SidebarItem: Hashable {
    case tab(AppTab)
    case mode(ExploreMode)
}

/// Regular width: a sidebar with the four tabs and the Explore modes as sub-rows, the tab's root in the content
/// column and the pushed screens in the detail column.
struct SidebarShell: View {
    let env: AppEnvironment
    let router: AppRouter
    let unread: UnreadBadge
    @State private var visibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(selection: selection) {
                row(.tab(.trips))
                row(.tab(.explore))
                ForEach(ExploreMode.allCases, id: \.self) { mode in
                    row(.mode(mode)).padding(.leading, Spacing.lg)
                }
                row(.tab(.alerts))
                row(.tab(.you))
            }
            .navigationTitle(Text(verbatim: "Voyager"))
            .accessibilityIdentifier("shell.sidebar")
        } content: {
            TabRoot(env: env, router: router, tab: router.selectedTab, showsModePicker: false)
        } detail: {
            detail
        }
    }

    private var selection: Binding<SidebarItem?> {
        mainBinding(
            get: { router.selectedTab == .explore ? .mode(router.exploreMode) : .tab(router.selectedTab) },
            set: { item in
                switch item {
                case .tab(let tab): router.open(.tab(tab))
                case .mode(let mode): router.open(.explore(mode))
                case nil: break
                }
            })
    }

    @ViewBuilder private func row(_ item: SidebarItem) -> some View {
        switch item {
        case .tab(let tab):
            Label(TabInfo.title(tab), systemImage: TabInfo.icon(tab))
                .badge(tab == .alerts ? unread.count : 0)
                .tag(item)
                .hoverEffectIfAvailable()
        case .mode(let mode):
            Label(TabInfo.modeTitle(mode), systemImage: TabInfo.modeIcon(mode))
                .tag(item)
                .hoverEffectIfAvailable()
        }
    }

    /// The first pushed route is the detail root; later pushes stack on it.
    private var detail: some View {
        let tab = router.selectedTab
        let path = router.path(tab)
        return NavigationStack(path: detailPath(tab)) {
            Group {
                if let first = path.first {
                    RouteDestination(env: env, router: router, route: first)
                } else {
                    EmptyState(icon: TabInfo.icon(tab), title: TabInfo.title(tab))
                }
            }
            .id(path.first)
            .navigationDestination(for: Route.self) { route in
                RouteDestination(env: env, router: router, route: route)
            }
        }
    }

    private func detailPath(_ tab: AppTab) -> Binding<[Route]> {
        mainBinding(
            get: { Array(router.path(tab).dropFirst()) },
            set: { router.paths[tab] = Array(router.path(tab).prefix(1)) + $0 })
    }
}
