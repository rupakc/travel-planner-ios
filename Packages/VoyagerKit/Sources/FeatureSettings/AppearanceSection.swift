import DesignSystem
import L10n
import SwiftUI

struct AppearanceSection: View {
    let model: SettingsModel

    var body: some View {
        SettingsGroup(title: L10n.text(K.privacy.section.appearance)) {
            Text(verbatim: L10n.text(K.common.theme.label))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            Picker(
                L10n.text(K.common.theme.label),
                selection: Binding(get: { model.theme }, set: { model.setTheme($0) })
            ) {
                Text(verbatim: L10n.text(K.common.theme.system)).tag(ThemePreference.system)
                Text(verbatim: L10n.text(K.common.theme.light)).tag(ThemePreference.light)
                Text(verbatim: L10n.text(K.common.theme.dark)).tag(ThemePreference.dark)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.theme")
        }
    }
}
