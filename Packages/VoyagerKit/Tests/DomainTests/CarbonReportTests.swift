import Foundation
import Testing
import TestFixtures
import VoyagerModel
@testable import Domain

@Suite struct CarbonReportTests {
    private func report() throws -> CarbonReport {
        let json = try JSONDecoder().decode(JSONValue.self, from: try Fixtures.data("json/carbon_trip.json"))
        return try #require(CarbonReport(json: json))
    }

    @Test func readsTotalsAndComparisons() throws {
        let report = try report()
        #expect(report.totalKg == 1000)
        #expect(report.perPersonKg == 500)
        #expect(report.travellers == 2)
        #expect(report.carKm == 6027)
        #expect(report.budgetShare == 0.25)
        #expect(report.annualBudgetKg == 2000)
    }

    @Test func keepsOnlyKnownCountedCategoriesInOrder() throws {
        #expect(try report().categories.map(\.key) == ["flights", "stays", "ground", "food"])
    }

    @Test func linesKeepKindParamsAndCrawlerSource() throws {
        let lines = try report().lines
        #expect(lines.count == 5)
        #expect(lines[1].params == ["city": "Paris", "nights": "4", "rooms": "1"])
        #expect(lines[2].params["km"] == "470.4")
        #expect(lines[4].params.isEmpty)
        let source = try #require(lines[1].crawlerSource)
        #expect(source.asOf == "2027-06-12")
        #expect(source.licenceURL?.host == "www.nationalarchives.gov.uk")
        #expect(lines[0].crawlerSource == nil)
    }

    @Test func railHintIsTheLargestSaving() throws {
        let hint = try #require(try report().railHint)
        #expect(hint.route == "LHR–CDG")
        #expect(hint.savingKg == 581)
        #expect(hint.railKm == 417)
    }

    @Test func sourcesNeedANameAndOnlyHttpsLinks() throws {
        let report = try report()
        #expect(report.sources.map(\.id) == ["google_tim", "desnz_2026", "evil"])
        #expect(report.sources[2].url == nil)
        #expect(report.sources[1].publisher == "DESNZ")
        #expect(report.crawlerSources.map(\.name) == ["UK DESNZ GHG conversion factors 2027", "grid-ember"])
        #expect(report.crawlerSources[1].asOf == nil)
    }

    @Test func olderBackendHasNoCrawlerFields() throws {
        let report = try #require(CarbonReport(json: ["total_kg": 12, "categories": [["key": "food", "kg": 12, "share": 1]]]))
        #expect(report.crawlerSources.isEmpty)
        #expect(report.lines.isEmpty)
        #expect(report.railHint == nil)
        #expect(report.travellers == 1)
        #expect(report.annualBudgetKg == 2000)
    }

    @Test func anythingButAnObjectIsNoReport() {
        #expect(CarbonReport(json: .null) == nil)
        #expect(CarbonReport(json: ["a"]) == nil)
    }
}
