import Foundation
import Testing
import UIKit

@testable import DesignSystem

@MainActor
struct FontRegistryTests {
    /// `ready()` waits for the asynchronous registration; `.timeLimit` makes a stuck registration
    /// fail the test instead of hanging the CI run.
    @Test(.timeLimit(.minutes(1)))
    func test_registerOnceIsIdempotent() async {
        FontRegistry.registerOnce()
        FontRegistry.registerOnce()
        await FontRegistry.ready()
        await FontRegistry.ready()  // later calls return immediately
        for name in FontRegistry.fileNames {
            #expect(UIFont(name: name, size: 12) != nil, "\(name) not registered")
        }
    }
}
