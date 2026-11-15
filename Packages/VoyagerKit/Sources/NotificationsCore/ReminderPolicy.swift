import Foundation
import VoyagerModel

/// Which on-device trip reminders may exist (R9), so a phone never buzzes twice or against the person's switches.
///
/// - Server push live (`features.notifications_v2`, `features.apns` and a registered device): the server sends T-30,
///   T-7, T-1 and the morning brief, so the local ones are dropped and only the check-out reminder stays.
/// - Otherwise the local reminders stay, each behind its category switch: `trip_reminders` for T-30, T-7, T-1 and
///   check-out, `morning_brief` for the day reminders.
///
/// A missing settings object (an older server) leaves every switch on, as it was before categories existed.
public struct ReminderPolicy: Sendable, Equatable {
    public var serverPushLive: Bool
    public var tripRemindersOn: Bool
    public var morningBriefOn: Bool

    public init(serverPushLive: Bool = false, tripRemindersOn: Bool = true, morningBriefOn: Bool = true) {
        self.serverPushLive = serverPushLive
        self.tripRemindersOn = tripRemindersOn
        self.morningBriefOn = morningBriefOn
    }

    /// `settings` is nil when the server has no notification settings; `devices` then counts as none.
    public init(features: RemoteFeatures, settings: NotificationSettings?) {
        self.init(
            serverPushLive: features.serverPushLive && (settings?.devices ?? 0) >= 1,
            tripRemindersOn: settings?.isEnabled(.tripReminders) ?? true,
            morningBriefOn: settings?.isEnabled(.morningBrief) ?? true)
    }

    /// The local reminder kinds: `t30`, `t7`, `t1`, `day<N>`, `last`.
    public func allows(kind: String) -> Bool {
        switch kind {
        case "last": return tripRemindersOn
        case "t30", "t7", "t1": return tripRemindersOn && !serverPushLive
        default: return kind.hasPrefix("day") && morningBriefOn && !serverPushLive
        }
    }
}
