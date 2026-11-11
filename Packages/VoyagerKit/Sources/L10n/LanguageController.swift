import Foundation
import Observation
import os
import VoyagerModel

/// Thread-safe mirror of the app language, so `L10n.text` and `Fmt` work from any isolation.
enum LanguageState {
    static let mirror = OSAllocatedUnfairLock<AppLanguage>(initialState: .en)
    /// Per-task override (tests, previews and snapshots of another language); never set in the app.
    @TaskLocal static var override: AppLanguage?
}

/// The app language: persists `tp_lang` (the web's key) and defaults to the device's preferred language.
@MainActor @Observable
public final class LanguageController {
    public static let shared = LanguageController(defaults: .standard, publishesCurrent: true)

    /// The language used by every `L10n` / `Fmt` call made without an override, from any isolation.
    public nonisolated static var current: AppLanguage {
        LanguageState.override ?? LanguageState.mirror.withLock { $0 }
    }

    /// Runs `body` with `language` as `current` (task-local: parallel tests do not interfere).
    public nonisolated static func withLanguage<Result>(
        _ language: AppLanguage,
        _ body: () throws -> Result
    ) rethrows -> Result {
        try LanguageState.$override.withValue(language, operation: body)
    }

    public static let storageKey = "tp_lang"

    @ObservationIgnored private var stored: AppLanguage
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let publishesCurrent: Bool

    /// Setting it persists to `UserDefaults` `tp_lang` and updates `current`.
    public var language: AppLanguage {
        get {
            access(keyPath: \.language)
            return stored
        }
        set {
            withMutation(keyPath: \.language) {
                stored = newValue
                defaults.set(newValue.rawValue, forKey: Self.storageKey)
                if publishesCurrent { LanguageState.mirror.withLock { $0 = newValue } }
            }
        }
    }

    /// The locale for number, date and currency formatting (`language.intlLocale`).
    public var locale: Locale { language.intlLocale }

    /// `publishesCurrent` is true only for `shared`; other instances (tests) leave `current` alone.
    public init(
        defaults: UserDefaults = .standard,
        preferred: [String] = Locale.preferredLanguages,
        publishesCurrent: Bool = false
    ) {
        self.defaults = defaults
        self.publishesCurrent = publishesCurrent
        let saved = defaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:))
        let initial = saved ?? AppLanguage.from(preferred: preferred)
        self.stored = initial
        if publishesCurrent { LanguageState.mirror.withLock { $0 = initial } }
    }
}
