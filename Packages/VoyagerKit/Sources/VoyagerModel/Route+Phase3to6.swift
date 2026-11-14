import Foundation

/// What a share sheet shares (Sharing-API `kind`; `quiz` and `status` arrive with Phase 5, R15).
public enum ShareTarget: Hashable, Sendable {
    case plan(id: Int)
    case recap(planID: Int)
    case savings
    /// A finished quiz session.
    case quiz(sessionID: String)
    /// An active trip; nil lets the server pick the caller's first active trip.
    case status(planID: Int?)
}

extension TelemetryRouteName {
    /// Templates of the Phase 3-6 routes: fixed strings, never an id, token, handle or session.
    static func phase3to6Template(for route: Route) -> String? {
        switch route {
        case .shareSheet: "/share-sheet"
        case .myShares: "/shares"
        case .openShare: "/share/:token"
        case .notificationSettings: "/notifications/settings"
        case .alertPrefs: "/alerts/preferences"
        case .priceStory: "/alerts/:id/story"
        case .tripToday: "/trips/:id/today"
        case .profile: "/u/:handle"
        case .profileEditor: "/profile"
        case .ideaDetail: "/feed/:id"
        case .ideas: "/feed"
        case .play: "/play"
        case .quiz: "/play/quiz"
        case .h2h: "/play/h2h/:id"
        default: nil
        }
    }
}
