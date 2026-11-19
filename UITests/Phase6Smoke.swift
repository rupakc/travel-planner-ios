import XCTest

/// Phase 6 (notifications 2.0): notification settings, with a quiet-hours edit that reaches the server.
final class Phase6Smoke: XCTestCase {
    @MainActor
    func test_quietHoursEditIsSaved() {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = Smoke.launch()
        Smoke.openTab(app, "You")

        let settings = Smoke.element(app, "settings.notificationSettings")
        Smoke.scrollTo(app, settings)
        settings.tap()
        Smoke.expect(Smoke.element(app, "notifications.root"))

        // The stub starts with quiet hours on (22:00 to 07:00): the two clocks show.
        let quiet = Smoke.element(app, "notifications.quiet.enabled")
        Smoke.scrollTo(app, quiet)
        Smoke.expect(Smoke.element(app, "notifications.quiet.start"))
        Smoke.flip(quiet)
        XCTAssertTrue(
            Smoke.eventually { !Smoke.element(app, "notifications.quiet.start").exists },
            "turning quiet hours off hides the clocks")
        XCTAssertTrue(Smoke.eventually { Smoke.stubSaw(prefix: "PUT /api/notification-settings") })

        Smoke.flip(quiet)
        Smoke.expect(Smoke.element(app, "notifications.quiet.start"))
        Smoke.expect(Smoke.element(app, "notifications.quiet.end"))
    }
}
