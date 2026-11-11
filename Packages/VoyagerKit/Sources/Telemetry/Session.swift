import Foundation

/// Idle-based session ids (30 minutes, like the web).
struct SessionClock: Sendable {
    static let idleLimit: TimeInterval = 30 * 60

    private(set) var id: String
    private(set) var lastActivity: Date

    init(now: Date) {
        id = UUID().uuidString.lowercased()
        lastActivity = now
    }

    /// Records activity at `now`; returns `true` when the session rolled over (a new id was issued).
    mutating func touch(now: Date) -> Bool {
        defer { lastActivity = now }
        guard now.timeIntervalSince(lastActivity) > Self.idleLimit else { return false }
        id = UUID().uuidString.lowercased()
        return true
    }
}
