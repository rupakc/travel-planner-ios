import Foundation

/// `instant` of the alert prefs: `all`, or `targets_only` (only target hits push or email; the rest waits for the digest).
public enum InstantMode: String, Codable, Sendable, Hashable, CaseIterable {
    case all
    case targetsOnly = "targets_only"
}

/// The quiet-hours window of the prefs (`HH:MM`, `[start, end)`, wrapping midnight; `start == end` means off).
public struct QuietHoursPref: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var start: String
    public var end: String

    public init(enabled: Bool = false, start: String = "22:00", end: String = "07:00") {
        self.enabled = enabled
        self.start = start
        self.end = end
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        enabled = json["enabled"].lenientBool ?? false
        start = json["start"].string ?? "22:00"
        end = json["end"].string ?? "07:00"
    }
}

/// Per-kind daily push/email caps, 1 to 10.
public struct DailyCaps: Codable, Sendable, Hashable {
    public var flight: Int
    public var hotel: Int
    public var activity: Int
    public var trip: Int

    public init(flight: Int = 3, hotel: Int = 3, activity: Int = 3, trip: Int = 3) {
        self.flight = flight
        self.hotel = hotel
        self.activity = activity
        self.trip = trip
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        flight = json["flight"].lenientInt ?? 3
        hotel = json["hotel"].lenientInt ?? 3
        activity = json["activity"].lenientInt ?? 3
        trip = json["trip"].lenientInt ?? 3
    }

    public subscript(kind: WatchKind) -> Int {
        get {
            switch kind {
            case .flight: flight
            case .hotel: hotel
            case .activity: activity
            case .trip: trip
            }
        }
        set {
            switch kind {
            case .flight: flight = newValue
            case .hotel: hotel = newValue
            case .activity: activity = newValue
            case .trip: trip = newValue
            }
        }
    }
}

/// `GET|PUT /alerts/preferences`.
public struct AlertPrefs: Codable, Sendable, Hashable {
    public var digestWeekly: Bool
    /// Has no effect while `digestWeekly` is false.
    public var digestPush: Bool
    /// ISO weekday, 1 = Monday.
    public var digestDay: Int
    public var instant: InstantMode
    public var quietHours: QuietHoursPref
    public var dailyCap: DailyCaps
    /// 0 to 120 minutes.
    public var groupWindowMin: Int
    /// Read-only: a mirror of the account setting; nil when unset (quiet hours are then not applied).
    public var timezone: String?
    /// Read-only.
    public var quietHoursActive: Bool

    public init(
        digestWeekly: Bool = false, digestPush: Bool = false, digestDay: Int = 1, instant: InstantMode = .all,
        quietHours: QuietHoursPref = QuietHoursPref(), dailyCap: DailyCaps = DailyCaps(), groupWindowMin: Int = 15,
        timezone: String? = nil, quietHoursActive: Bool = false
    ) {
        self.digestWeekly = digestWeekly
        self.digestPush = digestPush
        self.digestDay = digestDay
        self.instant = instant
        self.quietHours = quietHours
        self.dailyCap = dailyCap
        self.groupWindowMin = groupWindowMin
        self.timezone = timezone
        self.quietHoursActive = quietHoursActive
    }

    enum CodingKeys: String, CodingKey {
        case digestWeekly = "digest_weekly"
        case digestPush = "digest_push"
        case digestDay = "digest_day"
        case instant
        case quietHours = "quiet_hours"
        case dailyCap = "daily_cap"
        case groupWindowMin = "group_window_min"
        case timezone
        case quietHoursActive = "quiet_hours_active"
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard json.object != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Prefs is an object"))
        }
        func decoded<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
            guard !json[key].isNull, let data = try? JSONEncoder().encode(json[key]) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        digestWeekly = json["digest_weekly"].lenientBool ?? false
        digestPush = json["digest_push"].lenientBool ?? false
        digestDay = json["digest_day"].lenientInt ?? 1
        instant = json["instant"].string.flatMap(InstantMode.init(rawValue:)) ?? .all
        quietHours = decoded("quiet_hours", QuietHoursPref.self) ?? QuietHoursPref()
        dailyCap = decoded("daily_cap", DailyCaps.self) ?? DailyCaps()
        groupWindowMin = json["group_window_min"].lenientInt ?? 15
        timezone = json["timezone"].string
        quietHoursActive = json["quiet_hours_active"].lenientBool ?? false
    }

    /// The writable keys only: `timezone` and `quiet_hours_active` are the server's and never sent.
    public var writable: AlertPrefsPatch {
        AlertPrefsPatch(
            digestWeekly: digestWeekly, digestPush: digestPush, digestDay: digestDay, instant: instant,
            quietHours: quietHours, dailyCap: dailyCap, groupWindowMin: groupWindowMin)
    }
}

/// `PUT /alerts/preferences` body: any subset of the writable keys (nil keys are left out).
public struct AlertPrefsPatch: Codable, Sendable, Hashable {
    public var digestWeekly: Bool?
    public var digestPush: Bool?
    public var digestDay: Int?
    public var instant: InstantMode?
    public var quietHours: QuietHoursPref?
    public var dailyCap: DailyCaps?
    public var groupWindowMin: Int?

    public init(
        digestWeekly: Bool? = nil, digestPush: Bool? = nil, digestDay: Int? = nil, instant: InstantMode? = nil,
        quietHours: QuietHoursPref? = nil, dailyCap: DailyCaps? = nil, groupWindowMin: Int? = nil
    ) {
        self.digestWeekly = digestWeekly
        self.digestPush = digestPush
        self.digestDay = digestDay
        self.instant = instant
        self.quietHours = quietHours
        self.dailyCap = dailyCap
        self.groupWindowMin = groupWindowMin
    }

    enum CodingKeys: String, CodingKey {
        case digestWeekly = "digest_weekly"
        case digestPush = "digest_push"
        case digestDay = "digest_day"
        case instant
        case quietHours = "quiet_hours"
        case dailyCap = "daily_cap"
        case groupWindowMin = "group_window_min"
    }
}
