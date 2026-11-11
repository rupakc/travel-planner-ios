import Testing
import Domain
import VoyagerModel

@Suite struct RemixGoldenTests {
    @Test(arguments: PlanGolden.cases("remix"))
    func golden(_ c: PlanGolden.Case) {
        let actual: JSONValue
        switch c.fn {
        case "applyRemix": actual = Remix.apply(c.arg(0), presetID: c.arg(1).string ?? "")
        case "snapshotMetrics": actual = Remix.snapshotMetrics(c.arg(0))
        case "diffMetrics": actual = .array(Remix.diffMetrics(c.arg(0), c.arg(1), translate: PlanGolden.english))
        default:
            Issue.record("unhandled fn \(c.fn)")
            return
        }
        #expect(actual == c.output, "\(c.testDescription)")
    }

    @Test func fixturesArePresent() {
        #expect(PlanGolden.cases("remix").count == 37)
    }

    @Test func presetsMatchTheWeb() {
        #expect(Remix.presets.map(\.id) == ["week_later", "half_budget", "luxe", "slower_pace", "long_weekend"])
        #expect(Remix.presets.map(\.emoji) == ["\u{1F4C5}", "\u{1F4B8}", "\u{2728}", "\u{1F9D8}", "\u{26A1}"])
        #expect(Remix.presets[0].labelKey == "sections:remix.preset.week_later.label")
        #expect(Remix.presets[4].descriptionKey == "sections:remix.preset.long_weekend.description")
        // Every label and description exists in the web catalogue.
        for preset in Remix.presets {
            #expect(PlanGolden.english(preset.labelKey, [:]) != preset.labelKey)
            #expect(PlanGolden.english(preset.descriptionKey, [:]) != preset.descriptionKey)
        }
    }
}
