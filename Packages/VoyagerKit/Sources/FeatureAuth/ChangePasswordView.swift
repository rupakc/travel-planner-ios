import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv

/// Sets a new password. `forced` (the account carries a temporary password) has no cancel and cannot be dismissed.
public struct ChangePasswordView: View {
    let env: AppEnvironment
    let forced: Bool
    @State private var model: ChangePasswordModel
    @Environment(\.dismiss) private var dismiss

    @MainActor public init(env: AppEnvironment, forced: Bool) {
        self.env = env
        self.forced = forced
        _model = State(initialValue: ChangePasswordModel(env: env))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(verbatim: L10n.text(K.account.changePassword.title))
                    .font(VFont.display(.title))
                    .foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                if forced {
                    Text(
                        L10n.attributed(
                            K.account.changePassword.welcome, ["username": env.auth.session?.user.username ?? ""])
                    )
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
                }
                if let error = model.error {
                    Text(verbatim: error)
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("change-password.error")
                }
                field(L10n.text(K.account.changePassword.temporary), text: $model.current, tid: "change-password.current",
                      isNew: false)
                field(L10n.text(K.account.changePassword.new), text: $model.new, tid: "change-password.new",
                      placeholder: L10n.text(K.account.changePassword.newPlaceholder), isNew: true)
                field(L10n.text(K.account.changePassword.confirm), text: $model.confirm, tid: "change-password.confirm",
                      isNew: true)
                VButton(
                    model.isBusy ? L10n.text(K.account.changePassword.saving) : L10n.text(K.account.changePassword.submit),
                    tid: "change-password.submit"
                ) { Task { await model.submit() } }
                    .disabled(!model.canSubmit)
                if !forced {
                    VButton(L10n.text(K.account.admin.common.cancel), tid: "change-password.cancel", role: .secondary) {
                        dismiss()
                    }
                }
            }
            .padding(Spacing.lg)
            .readableWidth()
        }
        .background(SemanticColor.surface)
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(forced)
        .onChange(of: model.didSucceed) { _, done in
            if done && !forced { dismiss() }
        }
        .telemetryScreen("/change-password")
    }

    private func field(
        _ title: String, text: Binding<String>, tid: String, placeholder: String = "", isNew: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: title)
                .font(VFont.body(.subheadline, weight: .medium))
                .foregroundStyle(SemanticColor.text)
            SecureField(placeholder, text: text)
                .textContentType(isNew ? .newPassword : .password)
                .font(VFont.body(.body))
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.input))
                .overlay { RoundedRectangle(cornerRadius: Radius.input).strokeBorder(SemanticColor.border) }
                .accessibilityLabel(title)
                .accessibilityIdentifier(tid)
        }
    }
}
