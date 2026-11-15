import Foundation
import VoyagerModel

/// Maps a server notification `link` (a web path) to a `Route`. The mapping is the app's deep-link allow-list, which
/// lives in `AppShell`; the app installs it once at launch, so a link is never opened raw and the modules that show
/// or route notifications need not import the shell. Nothing installed means no link resolves.
public enum NotificationLinks {
    private static let resolver = ResolverBox()

    public static func install(_ resolve: @escaping @Sendable (String) -> Route?) { resolver.set(resolve) }

    public static func route(for link: String) -> Route? { resolver.get()?(link) }

    private final class ResolverBox: @unchecked Sendable {
        private let lock = NSLock()
        private var resolve: (@Sendable (String) -> Route?)?
        func set(_ value: @escaping @Sendable (String) -> Route?) {
            lock.lock()
            resolve = value
            lock.unlock()
        }
        func get() -> (@Sendable (String) -> Route?)? {
            lock.lock()
            defer { lock.unlock() }
            return resolve
        }
    }
}

/// Where a tap on a server notification (an inbox row or a push) goes (`R8`): trip and weather kinds open Trips Today
/// by `plan_id` (the trip detail while Today is not available, the inbox when there is no `plan_id`); any other kind
/// follows its allow-listed `link`; an unresolved social link opens the Ideas tab. Nil means "no opinion": the caller
/// keeps its own default (price rows open their watch).
public enum NotificationTarget {
    public static func route(kind: String?, planID: Int?, link: String?, todayAvailable: Bool = true) -> Route? {
        guard let kind else { return linkRoute(link) }
        if isTripKind(kind) {
            guard let planID, planID > 0 else { return .notifications }
            return todayAvailable ? .tripToday(planID: planID) : .planDetail(id: planID)
        }
        if let route = linkRoute(link) { return route }
        switch NotificationCategory.of(kind: kind) {
        case .social: return .ideas
        case .quiz: return .play
        case .none: return .notifications
        default: return nil
        }
    }

    /// The trip-phase and weather kinds, whose subject is a trip.
    public static func isTripKind(_ kind: String) -> Bool {
        switch kind {
        case "trip_t30", "trip_t7", "trip_t1", "trip_morning": true
        default: kind.hasPrefix("weather_")
        }
    }

    private static func linkRoute(_ link: String?) -> Route? {
        guard let link, !link.isEmpty else { return nil }
        return NotificationLinks.route(for: link)
    }
}
