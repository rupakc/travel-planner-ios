import L10n
import Testing

@Suite struct PluralTests {
    private let key = K.search.`import`.findInShots

    @Test func frenchZeroIsOne() {
        LanguageController.withLanguage(.fr) {
            #expect(L10n.text(key, count: 0) == "Trouver les lieux dans ma capture")
            #expect(L10n.text(key, count: 1) == "Trouver les lieux dans ma capture")
            #expect(L10n.text(key, count: 3) == "Trouver les lieux dans 3 captures")
        }
    }

    @Test func englishOther() {
        LanguageController.withLanguage(.en) {
            #expect(L10n.text(key, count: 1) == "Find the places in my screenshot")
            #expect(L10n.text(key, count: 0) == "Find the places in 0 screenshots")
            #expect(L10n.text(key, count: 3) == "Find the places in 3 screenshots")
            #expect(L10n.text(K.common.nav.unread, count: 7) == "7 unread")
        }
    }

    @Test func bengaliOne() {
        LanguageController.withLanguage(.bn) {
            #expect(L10n.text(key, count: 1) == "আমার স্ক্রিনশটে জায়গা খুঁজুন")
            #expect(L10n.text(key, count: 0) == "আমার স্ক্রিনশটে জায়গা খুঁজুন")
            #expect(L10n.text(key, count: 2) == "2টি স্ক্রিনশটে জায়গা খুঁজুন")
        }
    }
}
