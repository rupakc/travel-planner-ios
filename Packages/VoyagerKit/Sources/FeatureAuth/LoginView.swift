import AuthCore
import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv

/// Username + password sign-in, the four social buttons (coming soon) and, in Debug builds, a Server button.
public struct LoginView: View {
    let env: AppEnvironment
    @State private var model: LoginModel
    private let social: SocialSignInModel
    @State private var showServer = false

    @MainActor public init(env: AppEnvironment) {
        self.init(env: env, model: LoginModel(env: env), social: SocialSignInModel(env: env))
    }

    @MainActor init(env: AppEnvironment, model: LoginModel, social: SocialSignInModel) {
        self.env = env
        _model = State(initialValue: model)
        self.social = social
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if case .signedOut(reason: .sessionExpired) = env.auth.phase {
                    note(L10n.text(K.mobile.session.expired), tid: "login.notice")
                }
                if let error = model.error {
                    Text(verbatim: error)
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("login.error")
                }
                fields
                VButton(
                    model.isBusy ? L10n.text(K.account.login.submitting) : L10n.text(K.account.login.submit),
                    tid: "login.submit"
                ) { Task { await model.submit() } }
                    .disabled(!model.canSubmit)
                divider
                SocialSignInButtons(model: social)
                if env.build.isDebug {
                    VButton(L10n.text(K.mobile.server.title), tid: "login.server", role: .tonal, systemImage: "server.rack") {
                        showServer = true
                    }
                }
            }
            .padding(Spacing.lg)
            .readableWidth()
        }
        .background(SemanticColor.surface)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showServer) { ServerSheet(env: env) }
        .telemetryScreen("/login")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(K.account.login.title))
                .font(VFont.display(.title))
                .foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: L10n.text(K.account.login.tagline))
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.textMuted)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            label(L10n.text(K.account.login.username))
            input {
                TextField(L10n.text(K.account.login.usernamePlaceholder), text: $model.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("login.username")
            }
            label(L10n.text(K.account.login.password))
            input {
                HStack {
                    Group {
                        if model.showPassword {
                            TextField(L10n.text(K.account.login.passwordPlaceholder), text: $model.password)
                        } else {
                            SecureField(L10n.text(K.account.login.passwordPlaceholder), text: $model.password)
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("login.password")
                    Button {
                        model.showPassword.toggle()
                    } label: {
                        Image(systemName: model.showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(SemanticColor.textMuted)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(
                        model.showPassword ? L10n.text(K.account.login.hidePassword) : L10n.text(K.account.login.showPassword)
                    )
                    .accessibilityIdentifier("login.toggle-password")
                }
            }
        }
        .onSubmit { Task { await model.submit() } }
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.subheadline, weight: .medium))
            .foregroundStyle(SemanticColor.text)
    }

    private func input<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(VFont.body(.body))
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 44)
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.input))
            .overlay { RoundedRectangle(cornerRadius: Radius.input).strokeBorder(SemanticColor.border) }
    }

    private func note(_ text: String, tid: String) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.footnote))
            .foregroundStyle(SemanticColor.text)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.itemCard))
            .accessibilityIdentifier(tid)
    }

    private var divider: some View {
        HStack(spacing: Spacing.md) {
            Rectangle().fill(SemanticColor.border).frame(height: 1)
            Text(verbatim: L10n.text(K.auth.divider))
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
            Rectangle().fill(SemanticColor.border).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
