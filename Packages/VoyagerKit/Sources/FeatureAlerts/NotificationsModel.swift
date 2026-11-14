import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// Where a notification points: the watch a drop alert is about.
public struct AlertTarget: Equatable, Sendable {
    public var kind: WatchKind?
    public var watchID: Int?
}

/// The inbox: notifications newest first, paged, with mark-read (one or all). A tap marks the notification read
/// and follows `data.links.alerts` to the watch. A 404 from the server (an older backend) hides the inbox.
@MainActor @Observable
public final class NotificationsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
        /// The server has no notifications API: the inbox is hidden.
        case unavailable
    }

    public static let pageSize = 20

    public private(set) var phase: Phase = .loading
    public private(set) var items: [AppNotification] = []
    public private(set) var unread = 0
    public private(set) var total = 0
    public private(set) var isLoadingMore = false
    public var toast: ToastMessage?

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let now: @MainActor () -> Date

    public init(
        env: AppEnvironment, track: (@MainActor (TelemetryEvent) -> Void)? = nil, now: (@MainActor () -> Date)? = nil
    ) {
        self.env = env
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
        self.now = now ?? { Date() }
    }

    public var hasMore: Bool { items.count < total }

    public func load() async {
        if items.isEmpty { phase = .loading }
        do {
            let page = try await env.repos.notifications.page(unreadOnly: false, limit: Self.pageSize, offset: 0)
            items = page.items
            total = page.total
            unread = page.unread
            phase = .loaded
        } catch APIError.notFound {
            phase = .unavailable
        } catch {
            phase = .failed(ErrorCopy.message(kind: Self.kind(error), detail: (error as? APIError)?.userFacingDetail))
        }
    }

    public func loadMore() async {
        guard hasMore, !isLoadingMore, phase == .loaded else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await env.repos.notifications.page(unreadOnly: false, limit: Self.pageSize, offset: items.count)
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            total = page.total
            unread = page.unread
        } catch {
            toast = ToastMessage(AlertsModel.failureText(error, fallback: L10n.text(K.alerts.bell.loadFailed)))
        }
    }

    public func markRead(_ notification: AppNotification) async {
        guard notification.readAt == nil else { return }
        do {
            let count = try await env.repos.notifications.markRead(ids: [notification.id], all: false)
            stamp { $0.id == notification.id }
            unread = max(count, 0)
            track(.alertEvent(action: "inbox_read", kind: Self.kindToken(notification)))
        } catch {
            toast = ToastMessage(AlertsModel.failureText(error, fallback: L10n.text(K.alerts.checks.saveFailed)))
        }
    }

    public func markAllRead() async {
        guard unread > 0 else { return }
        do {
            let count = try await env.repos.notifications.markRead(ids: nil, all: true)
            stamp { _ in true }
            unread = max(count, 0)
            track(.alertEvent(action: "inbox_read_all", kind: "all"))
        } catch {
            toast = ToastMessage(AlertsModel.failureText(error, fallback: L10n.text(K.alerts.checks.saveFailed)))
        }
    }

    /// A tap: mark read, then focus the watch the notification is about (when it names one).
    public func open(_ notification: AppNotification) async {
        track(.alertEvent(action: "inbox_open", kind: Self.kindToken(notification)))
        if let target = Self.target(of: notification), target.watchID != nil || target.kind != nil {
            env.router.open(.alerts(kind: target.kind, watchID: target.watchID))
        }
        await markRead(notification)
    }

    public func ageText(_ notification: AppNotification) -> String? {
        guard let date = AlertDates.timestamp(notification.createdAt) else { return nil }
        return Fmt.relative(date.timeIntervalSince(now()))
    }

    // MARK: - Parsing

    /// `data.links.alerts` is a web path: `/alerts?watch=7` or `/alerts?kind=hotel&watch=4`. Falls back to
    /// `data.watch_id` (and `data.kind`) for rows without links.
    public static func target(of notification: AppNotification) -> AlertTarget? {
        let data = notification.data
        if let link = data["links"]["alerts"].string, let parsed = parse(link) { return parsed }
        guard let id = data["watch_id"].int, id > 0 else { return nil }
        return AlertTarget(kind: data["kind"].string.flatMap(WatchKind.init(rawValue:)), watchID: id)
    }

    static func parse(_ link: String) -> AlertTarget? {
        guard let components = URLComponents(string: link), components.path.hasSuffix("/alerts") || components.path == "alerts"
        else { return nil }
        let query = components.queryItems ?? []
        let kind = query.first { $0.name == "kind" }?.value.flatMap(WatchKind.init(rawValue:))
        let watchID = query.first { $0.name == "watch" }?.value.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        return AlertTarget(kind: kind, watchID: watchID)
    }

    /// The notification's kind as a telemetry token (a fixed vocabulary, never text).
    static func kindToken(_ notification: AppNotification) -> String {
        switch notification.kind {
        case "fare_drop", "price_drop", "watch_expired", "watch_error", "price_digest": notification.kind ?? "other"
        default: "other"
        }
    }

    private func stamp(where matches: (AppNotification) -> Bool) {
        let stamped = ISO8601DateFormatter().string(from: now())
        for index in items.indices where matches(items[index]) && items[index].readAt == nil {
            items[index].readAt = stamped
        }
    }

    private static func kind(_ error: any Error) -> ErrorPresentationKind {
        (error as? APIError)?.presentationKind ?? .other
    }

    // MARK: - Test seams

    func show(items: [AppNotification], unread: Int, total: Int? = nil) {
        self.items = items
        self.unread = unread
        self.total = total ?? items.count
        phase = .loaded
    }
}
