import Foundation

/// `GET|PUT /api/notification-settings`. Decoded leniently: a missing or wrong-typed key takes its default (every
/// category on, cap 3), unknown categories and keys are ignored.
public struct NotificationSettings: Decodable, Sendable, Hashable {
    public var categories: [NotificationCategory: Bool]
    /// The same value as the alert prefs' `quiet_hours`.
    public var quietHours: QuietHoursPref
    /// 1 to 10: non-price pushes per local day (price drops are exempt).
    public var dailyCap: Int
    /// Read-only: the account time zone; nil when unset or invalid (quiet hours are then not applied).
    public var timezone: String?
    public var quietHoursActive: Bool
    /// Read-only: whether the server can deliver to that platform.
    public var pushFCM: Bool
    public var pushAPNS: Bool
    /// Read-only: the caller's registered device count.
    public var devices: Int

    public static let capRange = 1...10

    public init(
        categories: [NotificationCategory: Bool] = [:], quietHours: QuietHoursPref = QuietHoursPref(enabled: true),
        dailyCap: Int = 3, timezone: String? = nil, quietHoursActive: Bool = false, pushFCM: Bool = false,
        pushAPNS: Bool = false, devices: Int = 0
    ) {
        self.categories = categories
        self.quietHours = quietHours
        self.dailyCap = dailyCap
        self.timezone = timezone
        self.quietHoursActive = quietHoursActive
        self.pushFCM = pushFCM
        self.pushAPNS = pushAPNS
        self.devices = devices
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard json.object != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Settings is an object"))
        }
        var parsed: [NotificationCategory: Bool] = [:]
        for category in NotificationCategory.allCases {
            let entry = json["categories"][category.rawValue]
            if let enabled = entry["enabled"].lenientBool ?? entry.lenientBool { parsed[category] = enabled }
        }
        categories = parsed
        var quiet = QuietHoursPref(enabled: false)
        if json["quiet_hours"].object != nil, let data = try? JSONEncoder().encode(json["quiet_hours"]),
            let value = try? JSONDecoder().decode(QuietHoursPref.self, from: data) {
            quiet = value
        }
        quietHours = quiet
        dailyCap = json["daily_cap"].lenientInt ?? 3
        timezone = json["timezone"].string
        quietHoursActive = json["quiet_hours_active"].lenientBool ?? false
        pushFCM = json["push"]["fcm"].lenientBool ?? false
        pushAPNS = json["push"]["apns"].lenientBool ?? false
        devices = json["devices"].lenientInt ?? 0
    }

    /// A category the server did not list counts as on (the default).
    public func isEnabled(_ category: NotificationCategory) -> Bool { categories[category] ?? true }
}

/// `PUT /api/notification-settings` body: any subset of the writable keys. `timezone`, `quiet_hours_active`, `push` and
/// `devices` are the server's and never sent.
public struct NotificationSettingsPatch: Encodable, Sendable, Hashable {
    public var categories: [NotificationCategory: Bool]?
    public var quietHours: QuietHoursPref?
    public var dailyCap: Int?

    public init(categories: [NotificationCategory: Bool]? = nil, quietHours: QuietHoursPref? = nil, dailyCap: Int? = nil) {
        self.categories = categories
        self.quietHours = quietHours
        self.dailyCap = dailyCap
    }

    enum CodingKeys: String, CodingKey {
        case categories
        case quietHours = "quiet_hours"
        case dailyCap = "daily_cap"
    }

    private struct Enabled: Encodable { let enabled: Bool }

    public func encode(to encoder: any Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        if let categories {
            var wire: [String: Enabled] = [:]
            for (category, enabled) in categories { wire[category.rawValue] = Enabled(enabled: enabled) }
            try box.encode(wire, forKey: .categories)
        }
        try box.encodeIfPresent(quietHours, forKey: .quietHours)
        try box.encodeIfPresent(dailyCap, forKey: .dailyCap)
    }

    public var isEmpty: Bool { categories == nil && quietHours == nil && dailyCap == nil }

    /// What the server would answer `422 notification_settings_invalid` to, checked before the call: a cap outside 1 to 10 or
    /// a quiet-hours time that is not a 24-hour `HH:MM`.
    public var isValid: Bool {
        if let dailyCap, !NotificationSettings.capRange.contains(dailyCap) { return false }
        if let quietHours, !Self.isClock(quietHours.start) || !Self.isClock(quietHours.end) { return false }
        return true
    }

    /// `other` on top of `self`: its keys win (two edits made while a save was in flight become one save).
    public func merging(_ other: NotificationSettingsPatch) -> NotificationSettingsPatch {
        var merged = categories ?? [:]
        for (category, enabled) in other.categories ?? [:] { merged[category] = enabled }
        return NotificationSettingsPatch(
            categories: merged.isEmpty ? nil : merged, quietHours: other.quietHours ?? quietHours,
            dailyCap: other.dailyCap ?? dailyCap)
    }

    static func isClock(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2, let hour = Int(parts[0]), let minute = Int(parts[1])
        else { return false }
        return (0..<24).contains(hour) && (0..<60).contains(minute)
    }
}

/// The iOS notification permission as Settings shows it.
public enum NotificationPermissionState: Sendable, Hashable {
    /// Not read yet.
    case unknown
    /// Never asked.
    case notDetermined
    case denied
    /// Authorized, provisional or ephemeral.
    case allowed
}
