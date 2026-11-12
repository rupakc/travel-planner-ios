import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// The seven languages in their own names; the choice applies at once.
struct LanguagePicker: View {
    let model: SettingsModel

    var body: some View {
        SettingsGroup(title: L10n.text(K.privacy.section.language)) {
            // VStack, not LazyVStack: seven rows, and lazy stacks hang hosted snapshot tests.
            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button { model.setLanguage(language) } label: {
                        HStack {
                            Text(verbatim: language.nativeName).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                            Spacer()
                            if model.language == language {
                                Image(systemName: "checkmark").foregroundStyle(SemanticColor.primary).accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.language == language ? .isSelected : [])
                    .accessibilityIdentifier("settings.language.\(language.rawValue)")
                }
            }
        }
    }
}
