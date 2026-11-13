import DesignSystem
import L10n
import Networking
import Observation
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// The account email for fare-alert mail (`PUT /api/auth/email`): saved on its own, empty clears it.
@MainActor @Observable
final class EmailModel {
    enum Status: Equatable { case idle, saved, invalid, conflict, failed(detail: String?) }

    private let env: AppEnvironment
    var text: String
    private(set) var saving = false
    private(set) var status = Status.idle

    init(env: AppEnvironment) {
        self.env = env
        text = env.auth.session?.user.email ?? ""
    }

    /// `local@domain.tld`, no spaces: the server's own check.
    nonisolated static func isEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        guard !value.contains(where: { $0.isWhitespace }) else { return false }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }
    }

    func edited() { if status == .saved { status = .idle } }

    func save() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saving else { return }
        if !trimmed.isEmpty, !Self.isEmail(trimmed) {
            status = .invalid
            return
        }
        saving = true
        status = .idle
        do {
            let stored = try await env.repos.preferences.setEmail(trimmed)
            text = stored ?? ""
            status = .saved
        } catch let error as APIError {
            switch error {
            case .client(let code, _, _, _) where code == 409: status = .conflict
            case .client(let code, _, _, _) where code == 422: status = .invalid
            default: status = .failed(detail: error.userFacingDetail)
            }
        } catch {
            status = .failed(detail: nil)
        }
        saving = false
    }

    /// The line under the field: the error, "Saved", or the help text.
    var message: (text: String, isError: Bool) {
        switch status {
        case .invalid: return (L10n.text(K.alerts.email.invalid), true)
        case .conflict: return (L10n.text(K.account.prefs.email.conflict), true)
        case .failed(let detail):
            if let detail, !detail.isEmpty { return (detail, true) }
            return (L10n.text(K.alerts.email.saveFailed), true)
        case .saved: return (L10n.text(K.alerts.email.saved), false)
        case .idle: return (L10n.text(K.alerts.email.helpOn), false)
        }
    }
}

struct EmailField: View {
    @Bindable var model: EmailModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label {
                Text(verbatim: L10n.text(K.alerts.email.label))
            } icon: {
                Image(systemName: "envelope").accessibilityHidden(true)
            }
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            TextField("name@example.com", text: $model.text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .onChange(of: model.text) { _, _ in model.edited() }
                .accessibilityIdentifier("prefs.email")
            VButton(L10n.text(K.alerts.email.save), tid: "prefs.emailSave", role: .secondary) {
                Task { await model.save() }
            }
            .disabled(model.saving)
            let line = model.message
            Text(verbatim: line.text)
                .font(VFont.body(.caption))
                .foregroundStyle(line.isError ? SemanticColor.destructive : SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("prefs.emailMessage")
        }
    }
}
