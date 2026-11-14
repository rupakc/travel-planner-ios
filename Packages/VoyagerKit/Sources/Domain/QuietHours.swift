import Foundation

/// The quiet-hours window of `AlertPrefs` / notification settings: `start` and `end` are local `HH:MM`.
public struct QuietWindow: Sendable, Hashable {
    public var enabled: Bool
    public var start: String
    public var end: String

    public init(enabled: Bool, start: String, end: String) {
        self.enabled = enabled
        self.start = start
        self.end = end
    }
}

/// What to do with a notification at a moment in time.
public enum QuietDecision: Sendable, Hashable {
    case deliverNow
    /// Held until `due`: the next wall-clock window end in the user's zone.
    case held(due: Date)
}

/// The Alerts-API quiet-hours rule (delivery rule 4), pinned by `Upstream/fixtures/alerts/quiet_hours_cases.json`:
/// the window is `[start, end)` and wraps midnight when `start > end`; `start == end`, `enabled == false`,
/// an unreadable `HH:MM`, a nil timezone or an unknown zone name mean "not applied". A held item is due at the
/// next local `end`, converted to UTC by the calendar, so a DST change in between is honoured.
public enum QuietHours {
    public static func evaluate(now: Date, timezone: String?, quiet: QuietWindow) -> QuietDecision {
        guard quiet.enabled, let timezone, let zone = TimeZone(identifier: timezone),
            let start = minutes(quiet.start), let end = minutes(quiet.end), start != end
        else { return .deliverNow }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let current = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let inside = start < end ? (start <= current && current < end) : (current >= start || current < end)
        guard inside else { return .deliverNow }
        let wanted = DateComponents(hour: end / 60, minute: end % 60, second: 0)
        guard let due = calendar.nextDate(after: now, matching: wanted, matchingPolicy: .nextTime) else {
            return .deliverNow
        }
        return .held(due: due)
    }

    /// `HH:MM` to minutes after midnight; nil when it is not a valid 24-hour time.
    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
            let hour = Int(parts[0]), let minute = Int(parts[1]), (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }
}
