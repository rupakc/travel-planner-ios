import DesignSystem
import L10n
import Networking
import SharedUI
import SwiftUI
import VoyagerEnv

/// Debug builds only (the button is hidden otherwise): points the app at another backend.
struct ServerSheet: View {
    let env: AppEnvironment
    @State private var text: String
    @State private var invalid = false
    @Environment(\.dismiss) private var dismiss

    @MainActor init(env: AppEnvironment) {
        self.env = env
        _text = State(initialValue: env.server.baseURL?.absoluteString ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: L10n.text(K.mobile.server.title))
                .font(VFont.display(.title3))
                .foregroundStyle(SemanticColor.text)
            Text(verbatim: L10n.text(K.mobile.server.hint))
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
            TextField("http://127.0.0.1:8001", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(Spacing.md)
                .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.input))
                .overlay { RoundedRectangle(cornerRadius: Radius.input).strokeBorder(SemanticColor.border) }
                .accessibilityIdentifier("server.url")
            if invalid {
                Text(verbatim: L10n.text(K.mobile.server.invalid))
                    .font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.destructive)
            }
            VButton(L10n.text(K.mobile.server.save), tid: "server.save") { save() }
            VButton(L10n.text(K.mobile.server.reset), tid: "server.reset", role: .secondary) { reset() }
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .background(SemanticColor.surface)
        .presentationDetents([.medium])
    }

    private func save() {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.host != nil else {
            invalid = true
            return
        }
        do {
            try env.server.setOverride(url)
            invalid = false
            dismiss()
        } catch {
            invalid = true
        }
    }

    private func reset() {
        try? env.server.setOverride(nil)
        text = env.server.baseURL?.absoluteString ?? ""
        invalid = false
        dismiss()
    }
}
