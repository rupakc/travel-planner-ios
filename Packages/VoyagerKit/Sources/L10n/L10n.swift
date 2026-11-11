import Foundation
import os
import VoyagerModel

/// Looks up catalogue strings (`Localizable.xcstrings`) in the current app language, falling back to English.
/// Callable from any isolation; the language comes from `LanguageController.current`.
public enum L10n {
    private struct CachedBundle: @unchecked Sendable { let bundle: Bundle? }
    private static let bundles = OSAllocatedUnfairLock<[String: CachedBundle]>(initialState: [:])
    private static let missing = "\u{1}missing\u{1}"

    /// The string for `key` with `{{name}}` filled from `args`. A plural key takes `count`.
    public static func text(_ key: LKey, _ args: [String: String] = [:], count: Int? = nil) -> String {
        checkArguments(key, args, count)
        return MarkupString.interpolate(template(key, count: count), args)
    }

    /// Like `text`, with `<strong>`/`<b>` as bold, `<a>` and the tags named in `links` as links; any other tag is
    /// dropped and its text kept. Argument values are inserted as plain text.
    public static func attributed(
        _ key: LKey,
        _ args: [String: String] = [:],
        count: Int? = nil,
        links: [String: URL] = [:]
    ) -> AttributedString {
        checkArguments(key, args, count)
        return MarkupString.attributed(template(key, count: count), args, links: links)
    }

    /// The localized string before `{{name}}` is filled: the plural form for `count` is already chosen.
    static func template(_ key: LKey, count: Int?) -> String {
        let language = LanguageController.current
        let found = lookup(key.id, in: language.bundleCode) ?? lookup(key.id, in: AppLanguage.en.bundleCode)
        guard let format = found else {
            // Not in the catalogue at all (generator drift): never surface the raw key path.
            return String(key.id.split(separator: ".").last ?? Substring(key.id))
        }
        guard key.plural else { return format }
        // The plural rule must follow the app language, not the device locale (fr: 0 is "one").
        return String(format: format, locale: language.intlLocale, count ?? 0)
    }

    private static func lookup(_ id: String, in code: String) -> String? {
        guard let bundle = bundle(for: code) else { return nil }
        let value = bundle.localizedString(forKey: id, value: missing, table: nil)
        return value == missing ? nil : value
    }

    private static func bundle(for code: String) -> Bundle? {
        bundles.withLock { cache -> Bundle? in
            if let cached = cache[code] { return cached.bundle }
            #if SWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE
            let loaded: Bundle? = nil  // local CLT mode builds without the String Catalog
            #else
            let loaded = Bundle.module.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
            #endif
            cache[code] = CachedBundle(bundle: loaded)
            return loaded
        }
    }

    private static func checkArguments(_ key: LKey, _ args: [String: String], _ count: Int?) {
        #if DEBUG
        assert(Set(args.keys) == key.placeholders, "L10n \(key.id): args \(args.keys.sorted()) != placeholders \(key.placeholders.sorted())")
        assert(key.plural == (count != nil), "L10n \(key.id): count must be given exactly for plural keys")
        #endif
    }
}
