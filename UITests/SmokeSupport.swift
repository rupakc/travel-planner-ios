import XCTest

/// Shared helpers of the Phase 3-6 smoke flows. Every flow runs against the stub backend (`tools/stub_backend`, started by
/// `scripts/ci/test-ui.sh` on `127.0.0.1:8765`): no real network, no push, canned data. The stub signs in any password.
@MainActor
enum Smoke {
    static let port = 8765
    static let base = "http://127.0.0.1:\(port)"

    // MARK: Stub

    /// Clears the stub's state and its call log, so a flow starts from the canned data.
    static func resetStub() {
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
            type(username, "smoke")
            // Return submits the form.
            type(app.secureTextFields["login.password"], "stub-password\n")
        }
        return app
    }

    /// Focuses a text field (a second tap when the first did not, as on iPad with a hardware keyboard) and types.
    static func type(_ field: XCUIElement, _ text: String) {
        for _ in 0..<4 {
            field.tap()
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            if XCTWaiter().wait(for: [focused], timeout: 3) == .completed { break }
        }
        field.typeText(text)
    }

    static func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Waits for `element` and taps it.
    static func tap(_ element: XCUIElement, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("not found: \(element)", file: file, line: line)
            dump()
            return
        }
        element.tap()
    }

    static func expect(_ element: XCUIElement, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let found = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(found, "not found: \(element)", file: file, line: line)
        if !found { dump() }
    }

    /// What the app showed and what the stub saw, printed when a step fails (the CI log is the only evidence).
    static func dump() {
        print("SMOKE stub calls: \(stubCalls())")
        print("SMOKE hierarchy: \(XCUIApplication().debugDescription)")
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
        _ = element.waitForExistence(timeout: 30)
        var swipes = 0
        while !element.isHittable && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists, "not found after scrolling: \(element)", file: file, line: line)
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

    /// A switch's own control sits at the trailing edge of its row.
    static func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
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
