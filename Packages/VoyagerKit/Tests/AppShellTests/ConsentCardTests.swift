import Foundation
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

@MainActor
@Suite struct ConsentStateTests {
    @Test func test_answeringHidesEverywhere() {
        let state = ConsentState()
        let telemetry = Telemetry()
        #expect(!state.isVisible(telemetry: telemetry, timeZone: "America/Chicago"))
        state.markAnswered()
        #expect(!state.isVisible(telemetry: telemetry, timeZone: "Europe/Berlin"))
    }
}
