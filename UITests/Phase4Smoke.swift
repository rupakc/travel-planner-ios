import XCTest

/// Phase 4 (share links 2.0): share the savings tally from Alerts, then revoke it in You > My shares.
final class Phase4Smoke: XCTestCase {
    @MainActor
    func test_shareThenRevokeInMyShares() {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = Smoke.launch()
        Smoke.openTab(app, "Alerts")

        Smoke.tap(Smoke.element(app, "alerts.savings.share"))
        Smoke.expect(Smoke.element(app, "share.sheet"))
        Smoke.tap(Smoke.element(app, "share.create"))
        Smoke.expect(Smoke.element(app, "share.url"))
        XCTAssertTrue(Smoke.stubSaw(prefix: "POST /api/shares"))
        Smoke.tap(Smoke.element(app, "share.close"))

        Smoke.openTab(app, "You")
        let mine = Smoke.element(app, "settings.myShares")
        Smoke.scrollTo(app, mine)
        mine.tap()

        Smoke.expect(Smoke.element(app, "shares.root"))
        Smoke.expect(Smoke.element(app, "shares.row"))
        Smoke.scrollAndTap(app, Smoke.element(app, "shares.revoke"))
        let yes = Smoke.element(app, "shares.revoke-yes")
        Smoke.expect(yes)
        Smoke.scrollAndTap(app, yes)

        Smoke.expect(Smoke.element(app, "shares.empty"))
        XCTAssertTrue(Smoke.eventually { Smoke.stubSaw(prefix: "DELETE /api/shares/") })
    }
}
