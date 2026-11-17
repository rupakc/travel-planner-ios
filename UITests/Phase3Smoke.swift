import XCTest

/// Phase 3 (price alerts 2.0): a watch that dropped, with its price story and the savings it caught.
final class Phase3Smoke: XCTestCase {
    @MainActor
    func test_watchWithADropShowsItsStory() {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = Smoke.launch()
        Smoke.openTab(app, "Alerts")

        Smoke.expect(Smoke.element(app, "alerts.watch.flight-7"))
        // The story (verdict, advice, chart) loads from /alerts/watches/flight/7/story.
        XCTAssertTrue(
            Smoke.eventually(timeout: 30) { Smoke.stubSaw(prefix: "GET /api/alerts/watches/flight/7/story") },
            "the card asks for its story")
        if !Smoke.stubSaw(prefix: "GET /api/alerts/watches/flight/7/story") { Smoke.dump() }
        Smoke.expect(Smoke.element(app, "alerts.story.flight-7"))
        Smoke.expect(Smoke.element(app, "alerts.story.verdict"))
        // The tally of observed drops: the stub reports $43 caught.
        Smoke.expect(Smoke.element(app, "alerts.savings.total"))
    }
}
