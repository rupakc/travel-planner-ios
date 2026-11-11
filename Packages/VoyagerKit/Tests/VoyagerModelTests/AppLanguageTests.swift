import Foundation
import Testing
import VoyagerModel

@Suite struct AppLanguageTests {
    @Test func test_fromPreferred() {
        #expect(AppLanguage.from(preferred: ["zh-TW", "en"]) == .zh)
        #expect(AppLanguage.from(preferred: ["pt-BR"]) == .en)
        #expect(AppLanguage.from(preferred: ["pt-BR", "de-AT"]) == .de)
        #expect(AppLanguage.from(preferred: ["zh-Hans-CN"]) == .zh)
        #expect(AppLanguage.from(preferred: ["FR_ca"]) == .fr)
        #expect(AppLanguage.from(preferred: []) == .en)
    }

    @Test func test_nativeNamesInWebOrder() {
        #expect(AppLanguage.allCases.map(\.nativeName) == [
            "English", "Español", "Deutsch", "Français", "हिन्दी", "中文（简体）", "বাংলা",
        ])
    }

    @Test func test_bundleCodeAndIntlLocale() {
        #expect(AppLanguage.zh.bundleCode == "zh-Hans")
        #expect(AppLanguage.bn.bundleCode == "bn")
        #expect(AppLanguage.zh.intlLocale.identifier == "zh-CN")
        #expect(AppLanguage.hi.intlLocale.identifier == "hi-IN")
        #expect(AppLanguage.bn.intlLocale.identifier == "bn-IN")
        #expect(AppLanguage.de.intlLocale.identifier == "de")
    }
}
