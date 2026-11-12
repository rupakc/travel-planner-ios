import L10n
import SwiftUI
import VoyagerModel

extension View {
    /// Pointer hover feedback on iPad (a no-op where there is no pointer UI).
    @ViewBuilder func hoverEffectIfAvailable() -> some View {
        #if canImport(UIKit)
        hoverEffect()
        #else
        self
        #endif
    }

    /// Hardware-keyboard shortcuts: ⌘F new search, ⌘N new chat, ⌘, You, ⌘1 to ⌘4 the tabs.
    func appShortcuts(_ router: AppRouter) -> some View {
        background {
            ShortcutButtons(router: router)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct ShortcutButtons: View {
    let router: AppRouter

    var body: some View {
        Group {
            Button(L10n.text(K.mobile.shortcuts.newSearch)) { router.open(.explore(.search)) }
                .keyboardShortcut("f", modifiers: .command)
            Button(L10n.text(K.mobile.shortcuts.newChat)) { router.open(.explore(.chat)) }
                .keyboardShortcut("n", modifiers: .command)
            Button(L10n.text(K.mobile.shortcuts.settings)) { router.open(.tab(.you)) }
                .keyboardShortcut(",", modifiers: .command)
            ForEach(Array(AppTab.allCases.enumerated()), id: \.offset) { index, tab in
                Button("\(L10n.text(K.mobile.shortcuts.tab)): \(TabInfo.title(tab))") { router.open(.tab(tab)) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
    }
}
