import Foundation

/// The app's languages, in the web's picker order (`frontend/src/i18n/languages.js`).
public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case en, es, de, fr, hi, zh, bn

    /// The language's own name, as the web's language picker shows it.
    public var nativeName: String {
        switch self {
        case .en: "English"
        case .es: "Español"
        case .de: "Deutsch"
        case .fr: "Français"
        case .hi: "हिन्दी"
        case .zh: "中文（简体）"
        case .bn: "বাংলা"
        }
    }

    /// The `.lproj` / String Catalog language code (`zh` ships as `zh-Hans`).
    public var bundleCode: String {
        self == .zh ? "zh-Hans" : rawValue
    }

    /// The locale for number, date and currency formatting (the web's `intlLocale`).
    public var intlLocale: Locale {
        switch self {
        case .zh: Locale(identifier: "zh-CN")
        case .hi: Locale(identifier: "hi-IN")
        case .bn: Locale(identifier: "bn-IN")
        default: Locale(identifier: rawValue)
        }
    }

    /// The first supported base language among `preferred` (BCP 47 tags, so `zh-TW` → `zh`),
    /// or `.en`. Pass `Locale.preferredLanguages`.
    public static func from(preferred: [String]) -> AppLanguage {
        for tag in preferred {
            let base = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            if let base, let language = AppLanguage(rawValue: String(base)) { return language }
        }
        return .en
    }
}
