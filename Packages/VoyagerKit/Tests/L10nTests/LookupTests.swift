import Foundation
import L10n
import Testing
import VoyagerModel

@Suite struct LookupTests {
    @Test func englishDefault() {
        LanguageController.withLanguage(.en) {
            #expect(L10n.text(K.common.nav.search) == "Search")
        }
    }

    @Test func switchToGerman() {
        LanguageController.withLanguage(.de) {
            #expect(L10n.text(K.common.nav.search) == "Suche")
        }
        LanguageController.withLanguage(.zh) {
            #expect(L10n.text(K.common.nav.search) == "搜索")
        }
    }

    @Test func interpolation() {
        LanguageController.withLanguage(.en) {
            let text = L10n.text(K.auth.comingSoon, ["provider": "Google"])
            #expect(text == "Google sign-in is coming soon — use your username and password for now.")
        }
    }

    @Test func keysDoNotLeakWhenTranslated() {
        for language in AppLanguage.allCases {
            LanguageController.withLanguage(language) {
                let text = L10n.text(K.common.nav.search)
                #expect(!text.isEmpty && !text.contains("common:") && !text.contains("nav."))
            }
        }
    }

    @Test func attributedStrongBold() {
        LanguageController.withLanguage(.en) {
            let result = L10n.attributed(K.alerts.body.tracking, ["title": "Paris <b>trip</b>"])
            #expect(String(result.characters) == "Tracking Paris <b>trip</b>")
            let bold = result.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            #expect(bold.count == 1)
            #expect(bold.first.map { String(result[$0.range].characters) } == "Paris <b>trip</b>")
        }
    }

    @Test func attributedDropsUnknownTagsKeepingText() {
        LanguageController.withLanguage(.en) {
            let key = K.alerts.hotel.notThisRemove
            let plain = L10n.attributed(key)
            #expect(String(plain.characters) == "Not this one? Remove it on your Alerts page.")
            #expect(plain.runs.allSatisfy { $0.link == nil })
            let url = URL(string: "https://example.com/alerts")
            let linked = L10n.attributed(key, links: ["pagelink": url].compactMapValues { $0 })
            #expect(linked.runs.filter { $0.link == url }.count == 1)
        }
    }
}
