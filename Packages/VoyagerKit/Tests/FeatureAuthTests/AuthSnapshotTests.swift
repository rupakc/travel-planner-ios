import AuthCore
import L10n
import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import XCTest

@testable import FeatureAuth

@MainActor
final class AuthSnapshotTests: XCTestCase {
    func test_loginWithComingSoonNote() async {
        let env = AppEnvironment.fake(user: nil)
        await assertSnapshots(
            of: {
                let note = L10n.text(K.auth.comingSoon, ["provider": "Google"])
                return LoginView(env: env, model: LoginModel(env: env), social: SocialSignInModel(env: env, note: note))
            },
            named: "login-note", devices: [.iPhoneSE, .iPadPro13], schemes: [.light, .dark])
    }

    func test_changePasswordForced() async {
        let env = AppEnvironment.fake(user: .sample)
        await assertSnapshots(
            of: { ChangePasswordView(env: env, forced: true) },
            named: "change-forced", devices: [.iPhoneSE], schemes: [.light])
    }
}
