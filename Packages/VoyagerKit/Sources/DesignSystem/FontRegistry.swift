import CoreText
import Foundation

/// Registers the bundled Inter and Sora TTFs for the process, once.
public enum FontRegistry {
    public static let fileNames = [
        "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold", "Sora-SemiBold", "Sora-Bold",
    ]

    /// Idempotent and thread-safe; call it as often as you like.
    public static func registerOnce() {
        _ = registered
    }

    private static let registered: Void = {
        for name in fileNames {
            let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf")
            guard let url else {
                assertionFailure("FontRegistry: bundled font \(name).ttf is missing")
                continue
            }
            // An "already registered" error is fine (another process-level registration).
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
