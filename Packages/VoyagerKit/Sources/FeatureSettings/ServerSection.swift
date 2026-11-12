import DesignSystem
import L10n
import Networking
import SharedUI
import SwiftUI

/// Debug builds only: point the app at another backend.
struct ServerSection: View {
    let model: SettingsModel
    @State private var text = ""
    @State private var invalid = false

    var body: some View {
        SettingsGroup(title: L10n.text(K.mobile.server.title)) {
            Text(verbatim: L10n.text(K.mobile.server.hint))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            TextField(model.env.server.baseURL?.absoluteString ?? "https://", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings.server.url")
            if invalid {
                Text(verbatim: L10n.text(K.mobile.server.invalid))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
            }
            HStack(spacing: Spacing.md) {
                VButton(L10n.text(K.mobile.server.reset), tid: "settings.server.reset", role: .secondary) {
                    invalid = false
                    text = ""
                    try? model.env.server.setOverride(nil)
                }
                VButton(L10n.text(K.mobile.server.save), tid: "settings.server.save") {
                    do {
                        try model.env.server.setOverride(URL(string: text.trimmingCharacters(in: .whitespaces)))
                        invalid = false
                    } catch {
                        invalid = true
                    }
                }
            }
        }
    }
}
