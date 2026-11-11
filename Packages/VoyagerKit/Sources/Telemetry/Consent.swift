import Foundation

public enum ConsentChoice: String, Sendable {
    case granted, denied
}

/// Consent rules from docs/Telemetry.md: devices in an EU, EEA, UK or Swiss time zone send nothing until
/// the user chooses; elsewhere telemetry is on until the user switches it off.
public enum Consent {
    /// `UserDefaults` key shared with the web's `localStorage` name.
    public static let defaultsKey = "tp_consent"

    private static let europeExceptions: Set<String> = [
        "Europe/Istanbul", "Europe/Moscow", "Europe/Minsk", "Europe/Kiev", "Europe/Kyiv",
    ]
    private static let atlantic: Set<String> = [
        "Atlantic/Reykjavik", "Atlantic/Canary", "Atlantic/Madeira", "Atlantic/Azores", "Atlantic/Faroe",
    ]

    public static func required(timeZone: String) -> Bool {
        if timeZone.hasPrefix("Europe/") { return !europeExceptions.contains(timeZone) }
        return atlantic.contains(timeZone)
    }

    static func stored(_ defaults: UserDefaults) -> ConsentChoice? {
        defaults.string(forKey: defaultsKey).flatMap(ConsentChoice.init(rawValue:))
    }

    static func store(_ choice: ConsentChoice, in defaults: UserDefaults) {
        defaults.set(choice.rawValue, forKey: defaultsKey)
    }

    /// Allowed when granted, or when there is no choice and consent is not required.
    static func allowed(defaults: UserDefaults, timeZone: String) -> Bool {
        switch stored(defaults) {
        case .granted: true
        case .denied: false
        case nil: !required(timeZone: timeZone)
        }
    }
}
