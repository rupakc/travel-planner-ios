import Foundation

/// What a "Watch price" button shows for one item (plan Task 3.4).
public enum QuickWatchState: Sendable, Hashable {
    /// Not watched yet (or not known to be): "Watch price".
    case idle
    /// The caller already watches it (a match answered `existing`): "Already watching".
    case existing(Int)
    /// Just watched with a one-tap watch; its first check is still queued: "Watching".
    case pending(Int)
    /// The shared active-watch limit was hit (`409 watch_limit`); a tap says so.
    case limit
    /// The server has no live prices (`features.live_prices` false, or `503 live_prices_off`): no button.
    case off

    public var isHidden: Bool { self == .off }
    public var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
    public var isWatching: Bool {
        switch self {
        case .existing, .pending: true
        default: false
        }
    }
}
