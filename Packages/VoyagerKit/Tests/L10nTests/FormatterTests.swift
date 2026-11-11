import Foundation
import L10n
import Testing

@Suite struct FormatterTests {
    @Test func currencyDE() {
        LanguageController.withLanguage(.de) {
            #expect(Fmt.currency(1234.5, code: "EUR").contains("1.234,50"))
        }
        LanguageController.withLanguage(.en) {
            #expect(Fmt.currency(1234.5, code: "USD") == "$1,234.50")
        }
    }

    @Test func badCurrencyCodeShowsCode() {
        LanguageController.withLanguage(.en) {
            #expect(Fmt.currency(12.5, code: "NOPE") == "NOPE 12.5")
            #expect(Fmt.currency(.nan, code: "USD") == "—")
        }
    }

    @Test func relativeNow() {
        LanguageController.withLanguage(.en) {
            #expect(Fmt.relative(0) == "now")
            #expect(Fmt.relative(-30) == "now")
            #expect(Fmt.relative(59) == "now")
            #expect(Fmt.relative(-3600).contains("hour"))
        }
        LanguageController.withLanguage(.de) {
            #expect(Fmt.relative(-5) == "jetzt")
        }
    }

    @Test func nonFiniteNumber() {
        #expect(Fmt.number(.nan) == "—")
        #expect(Fmt.number(.infinity) == "—")
        #expect(Fmt.number(-.infinity, fractionDigits: 2) == "—")
    }

    @Test func numberFollowsLanguage() {
        LanguageController.withLanguage(.de) {
            #expect(Fmt.number(1234.5) == "1.234,5")
            #expect(Fmt.number(2, fractionDigits: 2) == "2,00")
        }
        LanguageController.withLanguage(.en) {
            #expect(Fmt.number(1234.5) == "1,234.5")
        }
    }

    @Test func dateFollowsLanguage() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        LanguageController.withLanguage(.en) {
            #expect(Fmt.date(date).contains("2023"))
            #expect(Fmt.date(date, time: true).count > Fmt.date(date).count)
        }
    }
}
