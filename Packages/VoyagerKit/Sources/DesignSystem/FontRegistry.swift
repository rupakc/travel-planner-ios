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

    /// Returns once the batch registration has completed (immediately on later calls). Starts the
    /// registration itself if `registerOnce()` has not run yet.
    public static func ready() async {
        registerOnce()
        await completion.wait()
    }

    /// Completion latch: a continuation list behind a lock.
    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private var isDone = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func finish() {
            lock.lock()
            isDone = true
            let pending = waiters
            waiters = []
            lock.unlock()
            for waiter in pending { waiter.resume() }
        }

        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if isDone {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }
    }

    private static let completion = Completion()

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
        guard !urls.isEmpty else {
            completion.finish()
            return
        }
        let latch = completion
        // Errors such as "already registered" are fine: keep going. `done` marks the last callback.
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true) { _, done in
            if done { latch.finish() }
            return true
        }
    }()
}
