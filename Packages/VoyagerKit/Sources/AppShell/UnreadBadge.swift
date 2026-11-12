import Foundation
import Observation
import VoyagerModel

/// The unread-notification count on the Alerts tab, polled while the app is active.
@MainActor @Observable
final class UnreadBadge {
    private(set) var count = 0

    /// A failed poll keeps the last count.
    func refresh(_ repo: any NotificationsRepository) async {
        if let value = try? await repo.unreadCount() { count = max(value, 0) }
    }

    /// Polls every `interval` until the task is cancelled.
    func poll(_ repo: any NotificationsRepository, interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await refresh(repo)
            try? await Task.sleep(for: interval)
        }
    }

    func reset() { count = 0 }
}
