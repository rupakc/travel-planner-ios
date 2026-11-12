import AuthCore
import DesignSystem
import FeatureAuth
import FeatureOnboarding
import FeatureShare
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv

/// What the window shows. The order is fixed: a share link first (public, like the web's `SharePage`), then
/// sign-in, the forced password change, onboarding, and the shell.
enum GateScreen: Equatable {
    case share(token: String)
    case login
    case changePassword
    case onboarding
    case shell

    static func screen(phase: AuthPhase, onboardingCompleted: Bool, sharedToken: String?) -> GateScreen {
        if let sharedToken { return .share(token: sharedToken) }
        switch phase {
        case .signedOut: return .login
        case .needsPasswordChange: return .changePassword
        case .signedIn: return onboardingCompleted ? .shell : .onboarding
        }
    }
}

struct AuthGate: View {
    let env: AppEnvironment
    let router: AppRouter

    var screen: GateScreen {
        GateScreen.screen(
            phase: env.auth.phase, onboardingCompleted: env.device.onboardingCompleted, sharedToken: router.sharedToken)
    }

    var body: some View {
        Group {
            switch screen {
            case .share(let token):
                SharedPlanView(env: env, token: token)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            router.closeShare()
                        } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2).padding(Spacing.md)
                        }
                        .accessibilityLabel(Text(verbatim: L10n.text(K.plan.modal.close)))
                        .accessibilityIdentifier("shell.share.close")
                    }
                    .id(token)
            case .login:
                LoginView(env: env)
            case .changePassword:
                ChangePasswordView(env: env, forced: true)
            case .onboarding:
                OnboardingView(env: env, fromSettings: false) { _ in
                    // Skipping also enters the app; the step is kept so Settings can resume it.
                    env.device.onboardingCompleted = true
                }
            case .shell:
                ShellView(env: env, router: router)
            }
        }
        .animation(nil, value: screen)
    }
}
