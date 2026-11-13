import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry

/// New user with a temporary password of at least 8 characters.
struct CreateUserSheet: View {
    let model: UsersModel
    let dismiss: () -> Void
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var makeAdmin = false
    @State private var sending = false
    @State private var showHints = false

    private var passwordOK: Bool { UsersModel.validPassword(password) }
    private var usernameOK: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.account.admin.users.newUser)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                label(K.account.admin.users.usernameRequired)
                TextField(L10n.text(K.account.admin.table.username), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("admin.create.username")
                label(K.account.admin.users.emailOptional)
                TextField(L10n.text(K.account.admin.table.email), text: $email)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("admin.create.email")
                label(K.account.admin.users.tempPasswordRequired)
                SecureField(L10n.text(K.account.admin.reset.minPlaceholder), text: $password)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("admin.create.password")
                Toggle(isOn: $makeAdmin) {
                    Text(verbatim: L10n.text(K.account.admin.users.adminPrivileges)).foregroundStyle(SemanticColor.text)
                }
                .telemetryToggle(tid: "admin.create.admin", value: makeAdmin)
                if showHints && !usernameOK {
                    hint(L10n.text(K.account.admin.users.usernameRequired))
                } else if showHints && !passwordOK {
                    hint(L10n.text(K.account.admin.reset.tooShort))
                }
                if let error = model.actionError {
                    hint(ErrorCopy.message(kind: error.presentationKind, detail: error.userFacingDetail))
                }
                HStack(spacing: Spacing.md) {
                    VButton(L10n.text(K.account.admin.common.cancel), tid: "admin.create.cancel", role: .secondary, action: dismiss)
                    VButton(
                        sending ? L10n.text(K.account.admin.users.creating) : L10n.text(K.account.admin.users.createSubmit),
                        tid: "admin.create.submit", action: submit
                    )
                    .disabled(sending)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .onAppear { model.clearActionError() }
        .accessibilityIdentifier("admin.create.sheet")
    }

    private func submit() {
        guard usernameOK, passwordOK else { showHints = true; return }
        sending = true
        Task {
            let ok = await model.create(username: username, password: password, email: email, isAdmin: makeAdmin)
            sending = false
            if ok { dismiss() }
        }
    }

    private func label(_ key: LKey) -> some View {
        Text(verbatim: L10n.text(key)).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
    }

    private func hint(_ text: String) -> some View {
        Text(verbatim: text).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
    }
}

/// Sets a new password for one user; they must change it at next login.
struct ResetPasswordSheet: View {
    let model: UsersModel
    let username: String
    let isSelf: Bool
    let dismiss: () -> Void
    @State private var password = ""
    @State private var confirm = ""
    @State private var sending = false
    @State private var showHints = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.account.admin.reset.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                Text(verbatim: username).font(VFont.body(.headline)).foregroundStyle(SemanticColor.text)
                if isSelf {
                    Text(verbatim: L10n.text(K.account.admin.reset.selfWarning))
                        .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                }
                SecureField(L10n.text(K.account.admin.reset.newPassword), text: $password)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("admin.reset.password")
                SecureField(L10n.text(K.account.admin.reset.confirmPassword), text: $confirm)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("admin.reset.confirm")
                if showHints && !UsersModel.validPassword(password) {
                    hint(L10n.text(K.account.admin.reset.tooShort))
                } else if showHints && password != confirm {
                    hint(L10n.text(K.account.admin.reset.mismatch))
                }
                if let error = model.actionError {
                    hint(ErrorCopy.message(kind: error.presentationKind, detail: error.userFacingDetail))
                }
                HStack(spacing: Spacing.md) {
                    VButton(L10n.text(K.account.admin.common.cancel), tid: "admin.reset.cancel", role: .secondary, action: dismiss)
                    VButton(
                        sending ? L10n.text(K.account.admin.reset.submitting) : L10n.text(K.account.admin.reset.submit),
                        tid: "admin.reset.submit", action: submit
                    )
                    .disabled(sending)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .onAppear { model.clearActionError() }
        .accessibilityIdentifier("admin.reset.sheet")
    }

    private func submit() {
        guard UsersModel.validPassword(password), password == confirm else { showHints = true; return }
        sending = true
        Task {
            let ok = await model.resetPassword(username: username, newPassword: password, confirm: confirm)
            sending = false
            if ok { dismiss() }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(verbatim: text).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
    }
}
