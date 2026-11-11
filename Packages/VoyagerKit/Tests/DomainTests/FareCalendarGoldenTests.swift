import Testing
import VoyagerModel
@testable import Domain

@Suite struct FareCalendarGoldenTests {
    @Test(arguments: ExportGolden.cases("fareCalendar", fn: "shiftDates"))
    func shiftDatesMatchesWeb(_ golden: ExportGoldenCase) {
        let shifted = FareCalendar.shiftDates(
            departure: golden.arg(0).string ?? "", returnDate: golden.arg(1).string, offset: golden.arg(2).int ?? 0)
        #expect(shifted.departure == golden.output["departure_date"].string)
        #expect(shifted.returnDate == golden.output["return_date"].string)
    }

    @Test(arguments: ExportGolden.cases("fareCalendar", fn: "dayOffset"))
    func dayOffsetMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(FareCalendar.dayOffset(from: golden.arg(0).string ?? "", to: golden.arg(1).string ?? "") == golden.output.int)
    }

    @Test(arguments: ExportGolden.cases("fareCalendar", fn: "cheapestDeparture"))
    func cheapestDepartureMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(FareCalendar.cheapestDeparture(golden.arg(0).array ?? []) == golden.output.string)
    }

    @Test(arguments: ExportGolden.cases("fareCalendar", fn: "fareDelta"))
    func fareDeltaMatchesWeb(_ golden: ExportGoldenCase) {
        let delta = FareCalendar.fareDelta(golden.arg(0), golden.arg(1))
        #expect(delta == golden.output.double)
    }

    @Test(arguments: ExportGolden.cases("fareCalendar", fn: "daysUntil"))
    func daysUntilMatchesWeb(_ golden: ExportGoldenCase) {
        // The recorded run used TZ=UTC, so "today" is the UTC date.
        let days = FareCalendar.daysUntil(golden.arg(0).string, now: ExportGolden.date(golden.arg(1)), timeZone: ExportGolden.utc)
        #expect(days == golden.output.int)
    }

    @Test func fixturesCoverEveryDeclaredCase() throws {
        let counts = ["shiftDates": 5, "dayOffset": 4, "cheapestDeparture": 6, "fareDelta": 6, "daysUntil": 7]
        for (fn, count) in counts { #expect(ExportGolden.cases("fareCalendar", fn: fn).count == count, "\(fn)") }
        #expect(ExportGolden.cases("fareCalendar").count == (try ExportGolden.declaredCaseCount("fareCalendar")))
    }
}
