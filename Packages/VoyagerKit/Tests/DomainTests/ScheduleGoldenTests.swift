import Foundation
import Testing
import VoyagerModel
@testable import Domain

/// Swift output must equal what the web's `schedule.js` produced for the same arguments.
@Suite struct ScheduleGoldenTests {
    static let cases = ItineraryGoldenCase.all("schedule")

    static func run(_ c: ItineraryGoldenCase) -> JSONValue? {
        switch c.fn {
        case "scheduleDays":
            let edits: JSONValue = c.args.count > 1 ? c.arg(1) : .object([:])
            return Schedule.scheduleDays(c.arg(0), edits: edits)
        case "scheduleOrder":
            return .array(Schedule.scheduleOrder(c.arg(0)).map { .number(Double($0)) })
        case "listedInScheduleOrder":
            return .bool(Schedule.listedInScheduleOrder(c.arg(0)))
        case "timeRange":
            return .string(Schedule.timeRange(c.arg(0)) ?? "")
        case "transitLabel":
            return .string(Schedule.transitLabel(c.arg(0)) ?? "")
        case "pickedTimes":
            return Schedule.pickedTimes(c.arg(0))
        case "syncPlannedSlotTimes":
            return Schedule.syncPlannedSlotTimes(c.arg(0), c.arg(1))
        case "slotWhen":
            return .string(Schedule.slotWhen(c.arg(0)))
        default:
            return nil
        }
    }

    @Test func test_fixturesAreThere() {
        #expect(Self.cases.count >= 12)
        let known = Set(Self.cases.map(\.fn))
        #expect(known.isSuperset(of: [
            "scheduleDays", "scheduleOrder", "listedInScheduleOrder", "timeRange", "transitLabel", "pickedTimes",
            "syncPlannedSlotTimes", "slotWhen",
        ]))
    }

    @Test(arguments: ScheduleGoldenTests.cases)
    func test_matchesWeb(_ c: ItineraryGoldenCase) throws {
        let actual = try #require(Self.run(c), "no Swift port wired for \(c.fn)")
        #expect(actual == c.output, "\(c.testDescription)")
    }

    @Test func test_transitLabelUsesPassedTemplates() {
        let german = Schedule.TransitStrings(walk: "{{minutes}} Min. zu Fuß", walkKm: "{{minutes}} Min. zu Fuß · {{km}} km", transit: "~{{minutes}} Min. mit ÖPNV")
        let walk: JSONValue = ["mode": "walk", "minutes": 12, "km": 0.9]
        #expect(Schedule.transitLabel(walk, strings: german) == "🚶 12 Min. zu Fuß · 0.9 km")
        #expect(Schedule.transitLabel(["mode": "transit", "minutes": 25], strings: german) == "🚇 ~25 Min. mit ÖPNV")
        #expect(Schedule.transitLabel(nil) == nil)
    }
}
