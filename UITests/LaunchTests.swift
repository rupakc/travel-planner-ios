import XCTest

/// Launch-only smoke test. Task 38 adds the stub-backend smoke flow next to it.
final class LaunchTests: XCTestCase {
    @MainActor
    func test_launches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let start = ContinuousClock.now
        app.launch()
        let shown = app.windows.firstMatch.waitForExistence(timeout: 30)
        // Printed so CI logs separate the app's own launch time from the runner/simulator overhead around it.
        print("LaunchTests: launch to first window took \(ContinuousClock.now - start)")
        XCTAssertTrue(shown, "the app shows a window")
    }
}
