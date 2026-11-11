import Observation
import SwiftUI

public enum ThemePreference: String, CaseIterable, Sendable {
    case system, light, dark
}

/// The user's theme choice, stored in `UserDefaults` key `tp_theme` (same key as the web).
/// Light is the default, also when the stored value is junk.
@MainActor @Observable
public final class ThemeController {
    public static let defaultsKey = "tp_theme"

    @ObservationIgnored private let defaults: UserDefaults

    public var preference: ThemePreference {
        didSet {
            guard preference != oldValue else { return }
            defaults.set(preference.rawValue, forKey: Self.defaultsKey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preference = defaults.string(forKey: Self.defaultsKey).flatMap(ThemePreference.init(rawValue:)) ?? .light
    }

    /// For `.preferredColorScheme`; `nil` only for `.system`.
    public var colorScheme: ColorScheme? {
        switch preference {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
