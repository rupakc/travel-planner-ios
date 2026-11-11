import Foundation
import Testing
import VoyagerModel
@testable import Domain

@Suite struct PlanICSGoldenTests {
    @Test(arguments: ExportGolden.cases("planExport", fn: "buildPlanIcs"))
    func buildMatchesWeb(_ golden: ExportGoldenCase) {
        let input = golden.arg(0)
        let itinerary = input["itinerary"]
        let text = PlanICS.build(
            planName: input["planName"].string ?? "",
            searchData: input["searchData"],
            selections: input["selections"],
            itinerary: itinerary.isNull ? nil : itinerary,
            planID: input["planId"].int,
            now: ExportGolden.date(input["now"]),
            labels: .english
        )
        #expect(text == golden.output.string)
    }

    @Test(arguments: ExportGolden.cases("planExport", fn: "icsEscape"))
    func escapeMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(PlanICS.escape(golden.arg(0).string ?? "") == golden.output.string)
    }

    @Test(arguments: ExportGolden.cases("planExport", fn: "icsFold"))
    func foldMatchesWeb(_ golden: ExportGoldenCase) {
        let line = golden.arg(0).string ?? ""
        let folded = PlanICS.fold(line)
        #expect(folded == golden.output.string)
        for piece in folded.components(separatedBy: "\r\n") { #expect(piece.utf8.count <= 75) }
        #expect(folded.replacingOccurrences(of: "\r\n ", with: "") == line)
    }

    @Test(arguments: ExportGolden.cases("planExport", fn: "planFileName"))
    func fileNameMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(PlanICS.fileName(planName: golden.arg(0).string, ext: golden.arg(1).string ?? "") == golden.output.string)
    }

    @Test func fixturesCoverEveryFunction() {
        for fn in ["buildPlanIcs", "icsEscape", "icsFold", "planFileName"] {
            #expect(ExportGolden.cases("planExport", fn: fn).count >= 2, "\(fn)")
        }
    }

    @Test func everyLineEndsWithCRLFAndFitsTheFoldLimit() {
        let text = PlanICS.build(
            planName: "T", searchData: ["departure_date": "2027-04-01"],
            selections: ["hotel": ["name": .string(String(repeating: "Grand ", count: 30))]],
            planID: 1, now: Date(timeIntervalSince1970: 0), labels: .english)
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        for line in text.components(separatedBy: "\r\n") { #expect(line.utf8.count <= 75) }
    }

    @Test func slotsOnlyPlanNeedsNoItineraryPipeline() {
        let text = PlanICS.build(
            planName: "Slots", searchData: ["departure_date": "2027-04-01"],
            selections: ["itinerary_slots": [["key": "1-morning", "day_number": 1, "time_of_day": "morning", "activity": "Coffee"]]],
            planID: 9, now: Date(timeIntervalSince1970: 0), labels: .english)
        #expect(text.contains("UID:plan-9-slot-1-morning@voyager-travel-planner\r\n"))
        #expect(text.contains("DTSTART:20270401T090000\r\n"))
        #expect(text.contains("DTSTAMP:19700101T000000Z\r\n"))
    }
}
