import XCTest
import os

/// Shared helpers of the Phase 3-6 smoke flows. Every flow runs against the stub backend (`tools/stub_backend`, started by
/// `scripts/ci/test-ui.sh` on `127.0.0.1:8765`): no real network, no push, canned data. The stub signs in any password.
/// Last step a flow reached, and a watchdog that reports it when the flow hangs (a hung test leaves no other evidence).
enum Progress {
    private struct State { var last = "start"; var generation = 0 }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func mark(_ step: String) { state.withLock { $0.last = step } }

    static func reset() {
        let mine = state.withLock { value -> Int in value.generation += 1; value.last = "launch"; return value.generation }
        // Fires only when the flow is still on the same run after 170 s.
        DispatchQueue.global().asyncAfter(deadline: .now() + 170) {
            let (same, step) = state.withLock { ($0.generation == mine, $0.last) }
            guard same else { return }
            XCTFail("SMOKE still running after 170 s; last step: \(step); stub calls: \(Smoke.stubCallsOffMain().suffix(15))")
        }
    }
}

@MainActor
enum Smoke {
    static let port = 8765
    static let base = "http://127.0.0.1:\(port)"

    // MARK: Stub

    /// Clears the stub's state and its call log, so a flow starts from the canned data.
    static func resetStub() {
        Progress.reset()
        guard let url = URL(string: base + "/__reset") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in done.signal() }.resume()
        _ = done.wait(timeout: .now() + 15)
    }

    /// `"METHOD /path"` of every request the stub has seen since the last reset.
    static func stubCalls() -> [String] {
        guard let url = URL(string: base + "/__calls"), let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let calls = object["calls"] as? [String]
        else { return [] }
        return calls
    }

    nonisolated static func stubCallsOffMain() -> [String] {
        guard let url = URL(string: "http://127.0.0.1:8765/__calls"), let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let calls = object["calls"] as? [String]
        else { return [] }
        return calls
    }

    static func stubSaw(prefix: String) -> Bool { stubCalls().contains { $0.hasPrefix(prefix) } }

    // MARK: App

    /// Resets the stub, launches the app against it and signs in when the login screen shows (the session is kept in the
    /// Keychain, so only the first flow of a run does).
    static func launch() -> XCUIApplication {
        resetStub()
        let app = XCUIApplication()
        app.launchArguments += [
            "-VoyagerBaseURL", base,
            "-tp_onboarding_completed", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        // Signed in already (the Keychain keeps the session between flows) when a tab bar or the sidebar shows first.
        let username = app.textFields["login.username"]
        let shell = app.tabBars.firstMatch
        let sidebar = element(app, "shell.sidebar")
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, !username.exists, !shell.exists, !sidebar.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if username.exists {
            type(app, "login.username", "smoke")
            // Return submits the form.
            type(app, "login.password", "stub-password\n")
        }
        return app
    }

    /// Focuses a text field (tapped again, looked up afresh, when the screen re-rendered or the tap did not focus it, as on
    /// iPad) and types.
    static func type(_ app: XCUIApplication, _ id: String, _ text: String) {
        for _ in 0..<5 {
            let field = element(app, id)
            _ = field.waitForExistence(timeout: 20)
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).tap()
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element(app, id))
            if XCTWaiter().wait(for: [focused], timeout: 4) == .completed { break }
        }
        Progress.mark("type \(id)")
        if !element(app, id).exists { dump() }
        element(app, id).typeText(text)
    }

    static func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Waits for `element` and taps it.
    static func tap(_ element: XCUIElement, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        Progress.mark("tap \(element)")
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("not found: \(element)", file: file, line: line)
            dump()
            return
        }
        element.tap()
    }

    static func expect(_ element: XCUIElement, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        Progress.mark("expect \(element)")
        let found = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(found, "not found: \(element)", file: file, line: line)
        if !found { dump() }
    }

    /// What the app showed and what the stub saw, printed when a step fails (the CI log is the only evidence).
    static func dump() {
        let app = XCUIApplication()
        let ids = app.descendants(matching: .any).allElementsBoundByIndex.prefix(400).map(\.identifier).filter { !$0.isEmpty }
        let text = "SMOKE stub calls: \(stubCalls().suffix(25)); identifiers on screen: \(ids.joined(separator: ", "))"
        XCTFail(String(text.prefix(3500)))
    }

    /// Opens a tab: the tab bar on iPhone, the sidebar row on iPad.
    static func openTab(_ app: XCUIApplication, _ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.tabBars.buttons[title]
        let sidebar = element(app, "shell.sidebar")
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, !bar.exists, !sidebar.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        if bar.exists {
            bar.tap()
            return
        }
        guard sidebar.exists else {
            XCTFail("no tab bar and no sidebar", file: file, line: line)
            dump()
            return
        }
        let row = sidebar.staticTexts[title].firstMatch
        if row.exists { row.tap() } else { sidebar.buttons[title].firstMatch.tap() }
    }

    /// Scrolls the screen until `element` is on it (the screens are scroll views).
    static func scrollTo(_ app: XCUIApplication, _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        Progress.mark("scrollTo \(element)")
        _ = element.waitForExistence(timeout: 30)
        var swipes = 0
        while !element.isHittable && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists, "not found after scrolling: \(element)", file: file, line: line)
        if !element.exists { dump() }
    }

    /// Pops one screen on iPhone (the nav bar's back button); on iPad the previous screen is still in view.
    static func back(_ app: XCUIApplication) {
        if app.tabBars.firstMatch.exists, app.navigationBars.buttons.count > 0 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// Scrolls to `element` and taps it.
    static func scrollAndTap(_ app: XCUIApplication, _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        scrollTo(app, element, file: file, line: line)
        element.tap()
    }

    /// Flips a switch and checks its value changed: its own control sits at the trailing edge of its row, which on iPad
    /// can be a different place than on iPhone, so the other ways of hitting it are tried when the value stays.
    static func flip(_ toggle: XCUIElement) {
        Progress.mark("flip \(toggle)")
        let before = toggle.value as? String
        func changed() -> Bool { eventually(timeout: 3) { (toggle.value as? String) != before } }
        let width = max(toggle.frame.width, 80)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: (width - 36) / width, dy: 0.5)).tap()
        if changed() { return }
        let inner = toggle.switches.firstMatch
        if inner.exists { inner.tap(); if changed() { return } }
        toggle.tap()
        if changed() { return }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        _ = changed()
    }

    /// Polls `condition` for up to `timeout` seconds.
    static func eventually(timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return condition()
    }
}
