import Foundation
import TestFixtures
import Testing
import VoyagerModel

@testable import Domain

/// `Upstream/fixtures/alerts/quiet_hours_cases.json`: every backend and client must pass every case.
private struct QuietCase: Decodable, Sendable, CustomTestStringConvertible {
    struct Input: Decodable, Sendable {
        struct Window: Decodable, Sendable {
            let enabled: Bool
            let start: String
            let end: String
        }
        let nowUTC: String
        let timezone: String?
        let quietHours: Window

        enum CodingKeys: String, CodingKey {
            case nowUTC = "now_utc"
            case timezone
            case quietHours = "quiet_hours"
        }
    }
    struct Expected: Decodable, Sendable {
        let deliver: String
        let dueUTC: String

        enum CodingKeys: String, CodingKey {
            case deliver
            case dueUTC = "due_utc"
        }
    }
    let name: String
    let input: Input
    let expected: Expected

    var testDescription: String { name }

    static let all: [QuietCase] = {
        do {
            let data = try Fixtures.upstreamData("fixtures/alerts/quiet_hours_cases.json")
            return try JSONDecoder().decode([QuietCase].self, from: data)
        } catch {
            Issue.record("quiet_hours_cases.json unreadable: \(error)")
            return []
        }
    }()
}

private func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso) ?? .distantPast
}

private func decide(_ input: QuietCase.Input) -> QuietDecision {
    QuietHours.evaluate(
        now: date(input.nowUTC), timezone: input.timezone,
        quiet: QuietWindow(enabled: input.quietHours.enabled, start: input.quietHours.start, end: input.quietHours.end))
}

@Suite struct QuietHoursTests {
    @Test func test_goldenCasesAreThere() {
        #expect(QuietCase.all.count == 13)
    }

    @Test(arguments: QuietCase.all)
    fileprivate func test_goldenCases(_ c: QuietCase) {
        let decision = decide(c.input)
        switch c.expected.deliver {
        case "now":
            #expect(decision == .deliverNow, "\(c.name)")
        case "held":
            #expect(decision == .held(due: date(c.expected.dueUTC)), "\(c.name)")
        default:
            Issue.record("unknown deliver value in \(c.name)")
        }
    }

    @Test func test_nilTimezoneNeverHolds() {
        let window = QuietWindow(enabled: true, start: "00:00", end: "23:59")
        for hour in 0..<24 {
            let now = Date(timeIntervalSince1970: 1_700_000_000 + Double(hour) * 3600)
            #expect(QuietHours.evaluate(now: now, timezone: nil, quiet: window) == .deliverNow)
        }
        #expect(QuietHours.evaluate(now: .now, timezone: "Not/AZone", quiet: window) == .deliverNow)
    }

    @Test func test_wrapsMidnightEndExclusive() {
        let window = QuietWindow(enabled: true, start: "22:00", end: "07:00")
        let zone = "Europe/London"  // UTC+0 in January
        func decision(_ iso: String) -> QuietDecision { QuietHours.evaluate(now: date(iso), timezone: zone, quiet: window) }
        #expect(decision("2027-01-10T21:59:00Z") == .deliverNow)
        #expect(decision("2027-01-10T22:00:00Z") == .held(due: date("2027-01-11T07:00:00Z")))
        #expect(decision("2027-01-10T23:59:00Z") == .held(due: date("2027-01-11T07:00:00Z")))
        #expect(decision("2027-01-11T00:00:00Z") == .held(due: date("2027-01-11T07:00:00Z")))
        #expect(decision("2027-01-11T06:59:00Z") == .held(due: date("2027-01-11T07:00:00Z")))
        #expect(decision("2027-01-11T07:00:00Z") == .deliverNow)
    }

    @Test func test_malformedTimesAreNotApplied() {
        let now = date("2027-01-10T23:00:00Z")
        for (start, end) in [("25:00", "07:00"), ("22:00", "7:00"), ("22:00", "07:60"), ("", "07:00"), ("22-00", "07:00")] {
            let window = QuietWindow(enabled: true, start: start, end: end)
            #expect(QuietHours.evaluate(now: now, timezone: "Europe/London", quiet: window) == .deliverNow)
        }
    }
}
