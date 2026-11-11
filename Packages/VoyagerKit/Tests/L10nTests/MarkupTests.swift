import Foundation
import Testing
@testable import L10n

@Suite struct MarkupTests {
    @Test func interpolateReplacesOnceAndKeepsUnknown() {
        #expect(MarkupString.interpolate("{{a}} and {{ b }} and {{c}}", ["a": "{{b}}", "b": "B"]) == "{{b}} and B and {{c}}")
        #expect(MarkupString.interpolate("no placeholders", ["a": "x"]) == "no placeholders")
        #expect(MarkupString.interpolate("open {{a", ["a": "x"]) == "open {{a")
    }

    @Test func literalAngleBracketsStayText() {
        let result = MarkupString.attributed("Under <3 days, 5 < 6 and <> too", [:], links: [:])
        #expect(String(result.characters) == "Under <3 days, 5 < 6 and <> too")
    }

    @Test func selfClosingTagIsDropped() {
        let result = MarkupString.attributed("from <src/>.", [:], links: [:])
        #expect(String(result.characters) == "from .")
    }

    @Test func linkFromHrefOnlyForWebSchemes() {
        let good = MarkupString.attributed("<a href=\"https://example.com\">site</a>", [:], links: [:])
        #expect(good.runs.first?.link == URL(string: "https://example.com"))
        let bad = MarkupString.attributed("<a href=\"javascript:alert(1)\">site</a>", [:], links: [:])
        #expect(String(bad.characters) == "site")
        #expect(bad.runs.allSatisfy { $0.link == nil })
    }

    @Test func argumentValuesNeverBecomeMarkup() {
        let result = MarkupString.attributed("Hi <b>{{name}}</b>", ["name": "<strong>x</strong>"], links: [:])
        #expect(String(result.characters) == "Hi <strong>x</strong>")
    }

    @Test func nestedAndUnbalancedTags() {
        let result = MarkupString.attributed("a <strong>b <em>c</em> d</strong> e</b> f", [:], links: [:])
        #expect(String(result.characters) == "a b c d e f")
        let bold = result.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        #expect(bold.map { String(result[$0.range].characters) } == ["b c d"])
    }
}
