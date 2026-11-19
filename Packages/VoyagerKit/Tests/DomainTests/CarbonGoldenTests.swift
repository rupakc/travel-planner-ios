import Testing
import VoyagerModel
@testable import Domain

/// `CarbonRequest` against the web's `frontend/src/utils/carbon.js` (fixtures from `tools/golden/cases/carbon.json`).
@Suite struct CarbonGoldenTests {
    @Test(arguments: ExportGolden.cases("carbon", fn: "cheapest"))
    func cheapestMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(CarbonRequest.cheapest(golden.arg(0)) == golden.output)
    }

    @Test(arguments: ExportGolden.cases("carbon", fn: "trimFlight"))
    func trimFlightMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(CarbonRequest.trimFlight(golden.arg(0)) == golden.output)
    }

    @Test(arguments: ExportGolden.cases("carbon", fn: "trimItinerary"))
    func trimItineraryMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(CarbonRequest.trimItinerary(golden.arg(0)) == golden.output)
    }

    @Test(arguments: ExportGolden.cases("carbon", fn: "carbonRequestFromResults"))
    func resultsBodyMatchesWeb(_ golden: ExportGoldenCase) {
        let input = golden.arg(0)
        let body = CarbonRequest.fromResults(
            searchData: input["searchData"], results: input["results"], diet: input["diet"].string ?? "")
        #expect(body == golden.output)
    }

    @Test(arguments: ExportGolden.cases("carbon", fn: "carbonRequestFromSelections"))
    func selectionsBodyMatchesWeb(_ golden: ExportGoldenCase) {
        let input = golden.arg(0)
        let body = CarbonRequest.fromSelections(
            searchData: input["searchData"], selections: input["selections"], itinerary: input["itinerary"],
            diet: input["diet"].string ?? "")
        #expect(body == golden.output)
    }

    @Test(arguments: ExportGolden.cases("carbon", fn: "selectionsHaveTravel"))
    func travelMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(CarbonRequest.selectionsHaveTravel(golden.arg(0)) == golden.output.bool)
    }

    @Test(arguments: ExportGolden.cases("carbon", fn: "pctLabel"))
    func pctLabelMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(CarbonRequest.pctLabel(golden.arg(0).double) == golden.output.string)
    }

    @Test func fixturesCoverEveryDeclaredCase() throws {
        let counts = [
            "cheapest": 7, "trimFlight": 3, "trimItinerary": 3, "carbonRequestFromResults": 4,
            "carbonRequestFromSelections": 3, "selectionsHaveTravel": 5, "pctLabel": 12,
        ]
        for (fn, count) in counts { #expect(ExportGolden.cases("carbon", fn: fn).count == count, "\(fn)") }
        #expect(ExportGolden.cases("carbon").count == (try ExportGolden.declaredCaseCount("carbon")))
    }
}
