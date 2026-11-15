import Foundation
import VoyagerModel

/// What to do with a notification row on this device.
public enum NotificationDecision: Sendable, Hashable {
    case deliverNow
    /// Show it at `Date` (the end of the quiet-hours window).
    case holdUntil(Date)
    /// Never show it on this device (the in-app inbox row is untouched).
    case drop
}

/// The device-side copy of the server's delivery rules (`Notifications-API.md` and `Alerts-API.md`): category switch,
/// `instant = targets_only`, quiet hours (held until the window ends, dropped when that is more than 12 h away) and the
/// daily caps. The server always writes the in-app row; this decides only whether the phone buzzes, so a polled row never
/// breaks a rule the push path would have kept. Pure: the caller passes the time and today's delivered count.
public enum NotificationGate {
    /// The server drops a push held over this long, so the device does too.
    public static let maxHold: TimeInterval = 12 * 3600

    /// - Parameters:
    ///   - prefs: the alert prefs (`instant`, per-kind price caps); nil leaves those rules off.
    ///   - showsGame: false hides quiz rows (`hide_game`).
    ///   - deliveredToday: notifications this device already showed today in the row's cap bucket (price kind or non-price).
    public static func decide(
        row: AppNotification, settings: NotificationSettings, prefs: AlertPrefs? = nil, now: Date,
        showsGame: Bool = true, deliveredToday: Int = 0
    ) -> NotificationDecision {
        guard let category = NotificationCategory.of(kind: row.kind) else { return .drop }
        if category.isGameWording && !showsGame { return .drop }
        guard settings.isEnabled(category) else { return .drop }
        if category == .priceDrops, prefs?.instant == .targetsOnly, isInstantDrop(row), !isTargetHit(row) { return .drop }
        let window = QuietWindow(
            enabled: settings.quietHours.enabled, start: settings.quietHours.start, end: settings.quietHours.end)
        if case .held(let due) = QuietHours.evaluate(now: now, timezone: settings.timezone, quiet: window) {
            return due.timeIntervalSince(now) > maxHold ? .drop : .holdUntil(due)
        }
        if let cap = dailyCap(for: row, category: category, settings: settings, prefs: prefs), deliveredToday >= cap {
            return .drop
        }
        return .deliverNow
    }

    /// Price rows use the per-kind cap of the alert prefs (and are exempt from `daily_cap`); every other row uses `daily_cap`.
    /// The weekly digest has no cap.
    static func dailyCap(
        for row: AppNotification, category: NotificationCategory, settings: NotificationSettings, prefs: AlertPrefs?
    ) -> Int? {
        guard category == .priceDrops else { return settings.dailyCap }
        guard let prefs, let kind = watchKind(of: row) else { return nil }
        return prefs.dailyCap[kind]
    }

    /// The watch kind of a price row: `data.watch_kind`, `flight` for fare-watch rows, else the kind prefix.
    public static func watchKind(of row: AppNotification) -> WatchKind? {
        if let raw = row.data["watch_kind"].string ?? row.data["kind"].string, let kind = WatchKind(rawValue: raw) { return kind }
        guard let name = row.kind else { return nil }
        if name.hasPrefix("fare_") { return .flight }
        for kind in [WatchKind.hotel, .activity, .trip] where name.hasPrefix(kind.rawValue + "_") { return kind }
        return nil
    }

    /// The kinds `instant = targets_only` silences unless the target was hit.
    static func isInstantDrop(_ row: AppNotification) -> Bool {
        switch row.kind {
        case "fare_drop", "fare_low_level", "fare_cheaper_date", "hotel_drop", "activity_drop", "trip_drop": return true
        default: return false
        }
    }

    static func isTargetHit(_ row: AppNotification) -> Bool {
        row.dropData?.targetHit == true || row.kind?.hasSuffix("_target") == true
    }
}
