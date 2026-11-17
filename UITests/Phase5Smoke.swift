import XCTest

/// Phase 5 (social and Play): create a profile, then play the daily quiz (the stub's option `a` is always right).
final class Phase5Smoke: XCTestCase {
    @MainActor
    func test_createProfileThenPlayTheDailyQuiz() {
        continueAfterFailure = false
        executionTimeAllowance = 280
        let app = Smoke.launch()
        Smoke.openTab(app, "You")

        let profile = Smoke.element(app, "settings.profile")
        Smoke.scrollTo(app, profile)
        profile.tap()
        Smoke.expect(Smoke.element(app, "profile.editor"))

        let handle = Smoke.element(app, "profile.handle")
        Smoke.tap(handle)
        handle.typeText("smokey_traveler\n")
        let save = Smoke.element(app, "profile.save")
        // The save button enables once the live handle check answered "available".
        let enabled = NSPredicate(format: "isEnabled == true")
        let wait = XCTNSPredicateExpectation(predicate: enabled, object: save)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 30), .completed, "the handle check enables Save")
        save.tap()
        // The community rules show once before the first save.
        let accept = Smoke.element(app, "profile.rules.accept")
        let agree = app.buttons["I agree"]
        if !accept.waitForExistence(timeout: 20) { Smoke.tap(agree) } else { accept.tap() }
        Smoke.expect(Smoke.element(app, "profile.followers"))
        XCTAssertTrue(Smoke.eventually { Smoke.stubSaw(prefix: "PUT /api/social/profile") })

        Smoke.back(app)
        let play = Smoke.element(app, "settings.play")
        Smoke.scrollTo(app, play)
        play.tap()
        Smoke.expect(Smoke.element(app, "play.home"))
        Smoke.tap(Smoke.element(app, "play.daily.start"))
        Smoke.expect(Smoke.element(app, "play.quiz"))

        for _ in 0..<5 {
            Smoke.tap(Smoke.element(app, "play.quiz.option.a"))
            Smoke.tap(Smoke.element(app, "play.quiz.next"))
            // Let the next question replace this one before looking for its options.
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        Smoke.expect(Smoke.element(app, "play.result.score"))
        XCTAssertTrue(Smoke.stubSaw(prefix: "POST /api/play/quiz/"))
    }
}
