import Foundation

/// The root tabs (Play is reserved for Phase 5).
public enum AppTab: String, CaseIterable, Sendable {
    case trips, explore, alerts, you
}

/// The modes of the Explore tab.
public enum ExploreMode: String, CaseIterable, Sendable {
    case search, chat, compare, link, discover
}

/// Every place the app can navigate to. Features never import each other: cross-feature
/// navigation is `env.router.open(Route)`.
public enum Route: Hashable, Sendable {
    case tab(AppTab)
    case explore(ExploreMode)
    case results(TravelSearchRequest)
    case planDetail(id: Int)
    case myPlan
    case alerts(kind: WatchKind?, watchID: Int?)
    case notifications
    case nearby
    case settings
    case preferences
    case tasteProfile
    case admin
    case changePassword(forced: Bool)
    case onboarding(fromSettings: Bool)
    case share(token: String)
    case importLink(URL?)
}

@MainActor
public protocol AppRouting: AnyObject {
    func open(_ route: Route)
}

/// The route id sent with telemetry: a fixed template, never an id, token, URL or request.
public enum TelemetryRouteName {
    public static func template(for route: Route) -> String {
        switch route {
        case .tab(let tab):
            switch tab {
            case .trips: "/trips"
            case .explore: "/explore/search"
            case .alerts: "/alerts"
            case .you: "/settings"
            }
        case .explore(let mode):
            switch mode {
            case .search: "/explore/search"
            case .chat: "/chat"
            case .compare: "/explore/compare"
            case .link: "/explore/link"
            case .discover: "/explore/discover"
            }
        case .results: "/results"
        case .planDetail: "/plans/:id"
        case .myPlan: "/my-plan"
        case .alerts(_, let watchID): watchID == nil ? "/alerts" : "/alerts/:id"
        case .notifications: "/notifications"
        case .nearby: "/nearby"
        case .settings: "/settings"
        case .preferences: "/preferences"
        case .tasteProfile: "/taste"
        case .admin: "/admin"
        case .changePassword: "/change-password"
        case .onboarding: "/onboarding"
        case .share: "/share/:token"
        case .importLink: "/import"
        }
    }
}
