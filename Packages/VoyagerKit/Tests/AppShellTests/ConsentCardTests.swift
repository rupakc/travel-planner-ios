import Telemetry
import Testing

@testable import AppShell

@Suite struct ConsentCardTests {
    @Test func test_euWithNoChoiceShows() {
        #expect(ConsentPrompt.shouldShow(choice: nil, timeZone: "Europe/Berlin"))
        #expect(ConsentPrompt.shouldShow(choice: nil, timeZone: "Europe/London"))
    }

    @Test func test_aChoiceHides() {
        #expect(!ConsentPrompt.shouldShow(choice: .granted, timeZone: "Europe/Berlin"))
        #expect(!ConsentPrompt.shouldShow(choice: .denied, timeZone: "Europe/Berlin"))
    }

    @Test func test_elsewhereHides() {
        #expect(!ConsentPrompt.shouldShow(choice: nil, timeZone: "America/New_York"))
        #expect(!ConsentPrompt.shouldShow(choice: nil, timeZone: "Asia/Kolkata"))
    }
}
