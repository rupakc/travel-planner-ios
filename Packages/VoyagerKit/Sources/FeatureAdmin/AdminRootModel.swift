import Foundation
import Observation
import VoyagerEnv

/// Owns the three tab models. A non-admin gets no tabs and no network calls.
@MainActor @Observable
final class AdminRootModel {
    enum Tab: String, CaseIterable, Identifiable {
        case users, feedback, analytics
        var id: String { rawValue }
    }

    let env: AppEnvironment
    let users: UsersModel
    let feedback: AdminFeedbackModel
    let analytics: AnalyticsModel
    var selected: Tab = .users

    init(env: AppEnvironment) {
        self.env = env
        users = UsersModel(env: env)
        feedback = AdminFeedbackModel(env: env)
        analytics = AnalyticsModel(env: env)
    }

    var isAdmin: Bool { env.auth.session?.user.isAdmin == true }

    var tabs: [Tab] {
        guard isAdmin else { return [] }
        return analytics.isAvailable ? Tab.allCases : [.users, .feedback]
    }

    /// Probes the analytics endpoint once so a 404 hides its tab before it is chosen.
    func start() async {
        guard isAdmin else { return }
        await analytics.load()
        if !tabs.contains(selected) { selected = .users }
    }
}
