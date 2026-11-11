import CoreText
import Foundation

/// Registers the bundled Inter and Sora TTFs for the process, once.
///
/// Registration is one asynchronous batch (`CTFontManagerRegisterFontURLs`), so no caller ever blocks
/// on the font daemon (the synchronous per-file call hung a CI simulator run). Fonts become
/// available shortly after the call; until then SwiftUI falls back to the system font.
public enum FontRegistry {
    public static let fileNames = [
        "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold", "Sora-SemiBold", "Sora-Bold",
    ]

    /// Idempotent and thread-safe; never blocks. Call it as often as you like.
    public static func registerOnce() {
        _ = registered
    }

    private static let registered: Void = {
        var urls: [URL] = []
        for name in fileNames {
            let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf")
            if let url {
                urls.append(url)
            } else {
                assertionFailure("FontRegistry: bundled font \(name).ttf is missing")
            }
        }
        guard !urls.isEmpty else { return }
        // Errors such as "already registered" are fine: keep going.
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { _, _ in true }
    }()
}
