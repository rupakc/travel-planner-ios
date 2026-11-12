import Foundation
import Observation
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// What the Alerts tab shows first (set by `Route.alerts`).
public struct AlertsFocus: Hashable, Sendable {
    public var kind: WatchKind?
    public var watchID: Int?
}

/// The one navigation owner: the selected tab, each tab's own stack, and the sheets. Features reach it
/// through `env.router.open(_:)`; `screen_view` is emitted by each destination's `telemetryScreen` modifier.
@MainActor @Observable
public final class AppRouter: AppRouting {
    public var selectedTab: AppTab = .explore
    public var exploreMode: ExploreMode = .search
    /// Pushed routes per tab (the tab's root is not in the path).
    public var paths: [AppTab: [Route]] = [:]
    public var alertsFocus: AlertsFocus?
    /// The URL a `voyager://import` link carried, for the From-a-link mode.
    public var importURL: URL?
    public var myPlanPresented = false
    public var nearbyPresented = false
    /// A share link to show (works signed out).
    public var sharedToken: String?

    public init() {}

    public func path(_ tab: AppTab) -> [Route] { paths[tab] ?? [] }

    public func binding(for tab: AppTab) -> Binding<[Route]> {
        mainBinding(get: { [self] in path(tab) }, set: { [self] in paths[tab] = $0 })
    }

    public func open(_ route: Route) {
        switch route {
        case .tab(let tab):
            selectedTab = tab
        case .explore(let mode):
            exploreMode = mode
            selectedTab = .explore
            paths[.explore] = []
        case .results:
            push(route, on: .explore)
        case .planDetail:
            push(route, on: .trips)
        case .myPlan:
            myPlanPresented = true
        case .alerts(let kind, let watchID):
            alertsFocus = AlertsFocus(kind: kind, watchID: watchID)
            selectedTab = .alerts
            paths[.alerts] = []
        case .notifications:
            push(route, on: .alerts)
        case .nearby:
            nearbyPresented = true
        case .settings:
            selectedTab = .you
            paths[.you] = []
        case .preferences, .tasteProfile, .admin, .changePassword, .onboarding:
            push(route, on: .you)
        case .share(let token):
            sharedToken = token
        case .importLink(let url):
            importURL = url
            exploreMode = .link
            selectedTab = .explore
            paths[.explore] = []
        }
    }

    public func closeShare() { sharedToken = nil }

    /// Pops the last pushed route of `tab` (an onboarding or a form that finished).
    public func pop(_ tab: AppTab) {
        var current = path(tab)
        if !current.isEmpty { current.removeLast() }
        paths[tab] = current
    }

    private func push(_ route: Route, on tab: AppTab) {
        selectedTab = tab
        var current = path(tab)
        if current.last != route { current.append(route) }
        paths[tab] = current
    }
}

/// A `Binding` over main-actor state. SwiftUI calls bindings on the main thread; `assumeIsolated` states that
/// to the compiler whichever isolation the SDK gives the `Binding` closures.
@MainActor
func mainBinding<Value: Sendable>(
    get: @escaping @MainActor () -> Value,
    set: @escaping @MainActor (Value) -> Void
) -> Binding<Value> {
    Binding(
        get: { MainActor.assumeIsolated { get() } },
        set: { newValue in MainActor.assumeIsolated { set(newValue) } })
}
