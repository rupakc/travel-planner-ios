import Foundation

/// A notification category switch of `Notifications-API.md` (`categories.<name>.enabled`). The raw value is the wire
/// key and the telemetry `category` value. `nearby` is a client-side switch: the server never sends it.
public enum NotificationCategory: String, CaseIterable, Codable, Sendable, Hashable {
    case priceDrops = "price_drops"
    case tripReminders = "trip_reminders"
    case morningBrief = "morning_brief"
    case weather
    case nearby
    case social
    case quiz

    /// Quiz notifications carry game wording, so `hide_game` hides the switch and the notifications.
    public var isGameWording: Bool { self == .quiz }

    /// The category of a notification row `kind`, or nil for a kind this app does not know (clients ignore those).
    public static func of(kind: String?) -> NotificationCategory? {
        guard let kind else { return nil }
        switch kind {
        case "trip_t30", "trip_t7", "trip_t1": return .tripReminders
        case "trip_morning": return .morningBrief
        case "nearby_arrival": return .nearby
        case _ where Self.priceKinds.contains(kind): return .priceDrops
        case _ where kind.hasPrefix("weather_"): return .weather
        case _ where kind.hasPrefix("social_"): return .social
        case _ where kind.hasPrefix("quiz_"): return .quiz
        default: return nil
        }
    }

    /// Row kinds of the price alerts (`API-Reference.md`) and the weekly digest.
    static let priceKinds: Set<String> = [
        "fare_drop", "fare_target", "fare_low_level", "fare_cheaper_date", "hotel_drop", "hotel_target", "activity_drop",
        "activity_target", "trip_drop", "trip_target", "watch_expired", "watch_error", "price_digest",
    ]
}
