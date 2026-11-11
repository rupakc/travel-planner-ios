import Foundation
import SwiftUI
import Testing

@testable import DesignSystem

@MainActor
struct ThemeControllerTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "ThemeControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func test_defaultIsLight() {
        let controller = ThemeController(defaults: freshDefaults())
        #expect(controller.preference == .light)
        #expect(controller.colorScheme == .light)
    }

    @Test func test_persistsToTpTheme() {
        let defaults = freshDefaults()
        let controller = ThemeController(defaults: defaults)
        controller.preference = .dark
        #expect(defaults.string(forKey: "tp_theme") == "dark")
        #expect(controller.colorScheme == .dark)
        #expect(ThemeController(defaults: defaults).preference == .dark)
    }

    @Test func test_junkStoredValueFallsBackToLight() {
        let defaults = freshDefaults()
        defaults.set("sepia", forKey: "tp_theme")
        #expect(ThemeController(defaults: defaults).preference == .light)
    }

    @Test func test_systemHasNilColorScheme() {
        let defaults = freshDefaults()
        defaults.set("system", forKey: "tp_theme")
        #expect(ThemeController(defaults: defaults).colorScheme == nil)
    }
}
