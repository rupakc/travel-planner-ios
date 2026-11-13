import Foundation
import Observation
import VoyagerEnv
import VoyagerModel

/// The Feedback tab: entries filtered by page, category and minimum rating.
@MainActor @Observable
final class AdminFeedbackModel {
    nonisolated static let pages = ["search", "results", "chat", "preferences", "admin"]
    nonisolated static let categories = ["bug", "feature_request", "general", "praise"]
    nonisolated static let ratings = [1, 2, 3, 4, 5]

    private let repo: any AdminRepository
    var page: String?
    var category: String?
    var minRating: Int?
    private(set) var entries: [FeedbackEntry] = []
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var error: (any ErrorPresentable)?

    init(env: AppEnvironment) { repo = env.repos.admin }

    /// Changes whenever a filter changes; the view reloads on it.
    var filterKey: String { "\(page ?? "-")|\(category ?? "-")|\(minRating ?? 0)" }

    func load() async {
        loading = true
        defer { loading = false }
        let (page, category, minRating) = (page, category, minRating)
        do {
            let result = try await repo.feedback(page: page, category: category, minRating: minRating)
            // A newer filter may have been chosen while this call was in flight.
            guard page == self.page, category == self.category, minRating == self.minRating else { return }
            entries = result
            error = nil
            loaded = true
        } catch {
            if !(error is CancellationError) { self.error = adminPresentable(error) }
        }
    }
}
