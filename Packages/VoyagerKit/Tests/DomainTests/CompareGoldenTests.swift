import Testing
import VoyagerModel
@testable import Domain

@Suite struct CompareGoldenTests {
    @Test(arguments: ExportGolden.cases("compare", fn: "buildCompareRequests"))
    func requestsMatchWeb(_ golden: ExportGoldenCase) {
        #expect(CompareRules.requests(form: golden.arg(0)) == golden.output.array)
    }

    @Test(arguments: ExportGolden.cases("compare", fn: "bestByRow"))
    func bestByRowMatchesWeb(_ golden: ExportGoldenCase) {
        let summaries = golden.arg(0).array ?? []
        let expected = (golden.output.object ?? [:]).mapValues { Set(($0.array ?? []).compactMap(\.int)) }
        #expect(CompareRules.bestByRow(summaries) == expected)
    }

    @Test(arguments: ExportGolden.cases("compare", fn: "fmtDuration"))
    func durationMatchesWeb(_ golden: ExportGoldenCase) {
        #expect(CompareRules.durationText(minutes: golden.arg(0).double, format: { "\($0)h \($1)m" }) == golden.output.string)
    }

    @Test func fixturesCoverEveryFunction() {
        for fn in ["buildCompareRequests", "bestByRow", "fmtDuration"] {
            #expect(ExportGolden.cases("compare", fn: fn).count >= 4, "\(fn)")
        }
    }
}
