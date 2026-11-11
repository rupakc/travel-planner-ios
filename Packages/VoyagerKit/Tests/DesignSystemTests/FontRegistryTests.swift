import Foundation
import Testing
import UIKit

@testable import DesignSystem

@MainActor
@Suite(.serialized)
struct FontRegistryTests {
    /// Registration is asynchronous, so poll with a deadline: a stuck registration fails the test
    /// (and `.timeLimit` backs it up) instead of hanging the CI run.
    @Test(.timeLimit(.minutes(1)))
    func test_registerOnceIsIdempotent() async {
        FontRegistry.registerOnce()
        FontRegistry.registerOnce()
        let deadline = Date().addingTimeInterval(20)
        var missing = FontRegistry.fileNames
        while !missing.isEmpty, Date() < deadline {
            missing = missing.filter { UIFont(name: $0, size: 12) == nil }
            if !missing.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(missing.isEmpty, "not registered after 20 s: \(missing)")
    }
}
