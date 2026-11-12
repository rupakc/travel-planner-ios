import AuthCore
import Testing
import TestSupport

@testable import AppShell

@MainActor
@Suite struct AuthGateTests {
    @Test func test_signedOutShowsLogin() {
        #expect(GateScreen.screen(phase: .signedOut(reason: nil), onboardingCompleted: true, sharedToken: nil) == .login)
        #expect(GateScreen.screen(phase: .signedOut(reason: .sessionExpired), onboardingCompleted: false, sharedToken: nil) == .login)
    }

    @Test func test_needsPasswordChangeComesBeforeOnboarding() {
        #expect(GateScreen.screen(phase: .needsPasswordChange, onboardingCompleted: false, sharedToken: nil) == .changePassword)
    }

    @Test func test_onboardingThenShell() {
        #expect(GateScreen.screen(phase: .signedIn, onboardingCompleted: false, sharedToken: nil) == .onboarding)
        #expect(GateScreen.screen(phase: .signedIn, onboardingCompleted: true, sharedToken: nil) == .shell)
    }

    @Test func test_shareWorksSignedOut() {
        #expect(GateScreen.screen(phase: .signedOut(reason: nil), onboardingCompleted: false, sharedToken: "tok") == .share(token: "tok"))
    }

    @Test func test_gateFollowsTheEnvironment() {
        let env = AppEnvironment.fake(user: nil)
        let router = AppRouter()
        #expect(AuthGate(env: env, router: router).screen == .login)
        router.open(.share(token: "abc"))
        #expect(AuthGate(env: env, router: router).screen == .share(token: "abc"))

        let signedIn = AppEnvironment.fake()
        #expect(AuthGate(env: signedIn, router: AppRouter()).screen == .shell)
        signedIn.device.onboardingCompleted = false
        #expect(AuthGate(env: signedIn, router: AppRouter()).screen == .onboarding)
    }
}
