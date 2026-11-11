import Foundation
import Testing
import UIKit

@testable import DesignSystem

@MainActor
struct FontRegistryTests {
    /// `ready()` waits for the asynchronous registration. No `.timeLimit`: a cold simulator can stall the
    /// whole process for minutes; the CI wall-clock watchdog bounds a real hang.
    @Test
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
