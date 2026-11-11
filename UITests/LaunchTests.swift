import XCTest

/// Launch-only smoke test. Task 38 adds the stub-backend smoke flow next to it.
final class LaunchTests: XCTestCase {
    @MainActor
    func test_launches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "the app shows a window")
    }
}
