import Testing
import UIKit

@testable import DesignSystem

struct FontRegistryTests {
    @Test func test_registerOnceIsIdempotent() {
        FontRegistry.registerOnce()
        FontRegistry.registerOnce()
        for name in FontRegistry.fileNames {
            #expect(UIFont(name: name, size: 12) != nil, "\(name) not registered")
        }
    }
}
