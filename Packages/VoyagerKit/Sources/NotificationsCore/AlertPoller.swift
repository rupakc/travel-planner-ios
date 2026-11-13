import Foundation
import Networking
import VoyagerModel

/// Turns unread server notifications (price alerts) into local ones, once per id. Seen ids live in
/// `UserDefaults` (at most 200). A 404 from the endpoint (an older backend) disables polling for the launch.
public final class AlertPoller: @unchecked Sendable {
    public static let seenKey = "voyager.alertpoll.seen"
    public static let maxSeen = 200
    /// More than this many new rows at once (a first poll) show only the newest ones.
    static let maxPerPoll = 5

    private let repo: any NotificationsRepository
    private let center: any NotificationCenterClient
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var disabled = false

    public init(
        repo: any NotificationsRepository,
        center: any NotificationCenterClient = SystemNotificationCenter(),
        defaults: UserDefaults = .standard
    ) {
        self.repo = repo
        self.center = center
        self.defaults = defaults
    }

    public var isDisabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return disabled
    }

    private func disable() {
        lock.lock()
        disabled = true
        lock.unlock()
    }

    /// Never throws. Returns how many local notifications were posted.
    @discardableResult
    public func poll() async -> Int {
        guard !isDisabled, await center.isAuthorized() else { return 0 }
        let page: NotificationsPage
        do {
            page = try await repo.page(unreadOnly: true, limit: 50, offset: 0)
        } catch let error as APIError {
            if case .notFound = error { disable() }
            return 0
        } catch {
            return 0
        }
        var seen = defaults.array(forKey: Self.seenKey)?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
        let known = Set(seen)
        let fresh = page.items.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return 0 }
        var posted = 0
        for item in fresh.prefix(Self.maxPerPoll) {
            guard let title = Self.clean(item.title) ?? Self.clean(item.body) else { continue }
            let body = Self.clean(item.title) == nil ? "" : (Self.clean(item.body) ?? "")
            await center.add(LocalNotification(
                id: "alert-\(item.id)", title: title, body: body, userInfo: Self.userInfo(item)
            ))
            posted += 1
        }
        seen.append(contentsOf: fresh.map(\.id))
        defaults.set(Array(seen.suffix(Self.maxSeen)), forKey: Self.seenKey)
        return posted
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }

    /// The tap payload: `route: alerts`, plus the watch the row is about when the server named one.
    static func userInfo(_ item: AppNotification) -> [String: String] {
        var info = ["route": "alerts"]
        if let kind = item.data["kind"].string, WatchKind(rawValue: kind) != nil { info["kind"] = kind }
        if let value = item.data["watch_id"].double, value.isFinite, value >= 1, value <= 1e9 {
            info["watch_id"] = String(Int(value.rounded()))
        }
        return info
    }
}
