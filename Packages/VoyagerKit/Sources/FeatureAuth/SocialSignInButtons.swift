import AuthCore
import DesignSystem
import L10n
import Observation
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv

/// Drives the four social buttons. Until the backend configures a provider, a tap only explains that it is coming.
@MainActor @Observable
public final class SocialSignInModel {
    /// The inline "coming soon" (or failure) note shown below the buttons.
    public var note: String?

    @ObservationIgnored private let env: AppEnvironment

    public init(env: AppEnvironment, note: String? = nil) {
        self.env = env
        self.note = note
    }

    public func tap(_ provider: AuthProviderID) async {
        let known = await env.providers.providers()
        let info = known[provider] ?? AuthProviderInfo(id: provider, configured: false)
        do {
            try await env.auth.signIn(with: provider, info: info)
            note = nil
        } catch is CancellationError {
            return
        } catch AuthError.comingSoon(let which) {
            show(L10n.text(K.auth.comingSoon, ["provider": which.displayName]))
        } catch {
            show(L10n.text(K.errors.generic))
        }
    }

    private func show(_ text: String) {
        note = text
        LiveRegion.announce(text)
    }
}

/// Apple, Google, Facebook, GitHub, always visible, in the providers' own brand colours (the web's
/// `SocialSignInButtons.jsx`). These are the only literal colours outside DesignSystem.
public struct SocialSignInButtons: View {
    @State private var model: SocialSignInModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.telemetryRoute) private var route

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: SocialSignInModel(env: env))
    }

    @MainActor init(model: SocialSignInModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(AuthProviderID.allCases, id: \.self) { provider in
                let style = Self.style(provider, dark: scheme == .dark)
                Button {
                    Telemetry.shared.track(.uiTap(tid: "auth.provider.\(provider.rawValue)", route: route))
                    Task { await model.tap(provider) }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        glyph(provider)
                        Text(verbatim: L10n.text(K.auth.continueWith, ["provider": provider.displayName]))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(VFont.body(.headline, weight: .semibold))
                    .foregroundStyle(style.foreground)
                    .padding(.horizontal, Spacing.lg)
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .background(style.background, in: Capsule())
                    .overlay { if let border = style.border { Capsule().strokeBorder(border, lineWidth: 1) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("auth.provider.\(provider.rawValue)")
            }
            if let note = model.note {
                Text(verbatim: note)
                    .font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Self.noteBackground, in: RoundedRectangle(cornerRadius: Radius.itemCard))
                    .accessibilityIdentifier("auth.coming-soon")
            }
        }
    }

    private static var noteBackground: Color { SemanticColor.surfaceRaised }

    @ViewBuilder
    private func glyph(_ provider: AuthProviderID) -> some View {
        switch provider {
        case .apple: Image(systemName: "apple.logo").accessibilityHidden(true)
        case .google: Text(verbatim: "G").font(.system(size: 18, weight: .bold)).accessibilityHidden(true)
        case .facebook: Text(verbatim: "f").font(.system(size: 20, weight: .bold)).accessibilityHidden(true)
        case .github: Image(systemName: "chevron.left.forwardslash.chevron.right").accessibilityHidden(true)
        }
    }

    struct BrandStyle {
        let background: Color
        let foreground: Color
        let border: Color?
    }

    /// Fixed brand colours (light and dark variants), never themed.
    static func style(_ provider: AuthProviderID, dark: Bool) -> BrandStyle {
        switch provider {
        case .apple:
            return dark
                ? BrandStyle(background: rgb(0xFFFFFF), foreground: rgb(0x000000), border: nil)
                : BrandStyle(background: rgb(0x000000), foreground: rgb(0xFFFFFF), border: nil)
        case .google:
            return dark
                ? BrandStyle(background: rgb(0x131314), foreground: rgb(0xE3E3E3), border: rgb(0x8E918F))
                : BrandStyle(background: rgb(0xFFFFFF), foreground: rgb(0x1F1F1F), border: rgb(0x747775))
        case .facebook:
            return BrandStyle(background: rgb(0x1877F2), foreground: rgb(0xFFFFFF), border: nil)
        case .github:
            return dark
                ? BrandStyle(background: rgb(0xF6F8FA), foreground: rgb(0x24292F), border: nil)
                : BrandStyle(background: rgb(0x24292F), foreground: rgb(0xFFFFFF), border: nil)
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
