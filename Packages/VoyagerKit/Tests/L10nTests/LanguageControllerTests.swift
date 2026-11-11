import Foundation
import L10n
import Testing
import VoyagerModel

@MainActor @Suite struct LanguageControllerTests {
    private func freshDefaults() throws -> UserDefaults {
        let name = "L10nTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func persistsTpLang() throws {
        let defaults = try freshDefaults()
        let controller = LanguageController(defaults: defaults, preferred: ["en-US"])
        #expect(controller.language == .en)
        controller.language = .de
        #expect(defaults.string(forKey: "tp_lang") == "de")
        #expect(controller.locale.identifier == "de")
        let reopened = LanguageController(defaults: defaults, preferred: ["fr"])
        #expect(reopened.language == .de)
    }

    @Test func defaultsToPreferredLanguage() throws {
        let controller = LanguageController(defaults: try freshDefaults(), preferred: ["zh-Hans-CN", "en"])
        #expect(controller.language == .zh)
        let unsupported = LanguageController(defaults: try freshDefaults(), preferred: ["ja-JP"])
        #expect(unsupported.language == .en)
    }

    @Test func ignoresUnknownStoredValue() throws {
        let defaults = try freshDefaults()
        defaults.set("xx", forKey: "tp_lang")
        #expect(LanguageController(defaults: defaults, preferred: ["es"]).language == .es)
    }

    @Test func overrideWinsOverCurrent() {
        let outside = LanguageController.current
        LanguageController.withLanguage(.bn) { #expect(LanguageController.current == .bn) }
        #expect(LanguageController.current == outside)
    }
}
