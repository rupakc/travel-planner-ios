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
    /// iPhone SE on a canvas tall enough to show the whole form (note included), plus iPad, light and dark.
    private static let tall: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 1100)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 1100)),
        .padLight, .padDark,
    ]

    func test_loginWithComingSoonNote() async {
        let env = AppEnvironment.fake(user: nil)
        await assertSnapshots(
            of: {
                let note = L10n.text(K.auth.comingSoon, ["provider": "Google"])
                return LoginView(env: env, model: LoginModel(env: env), social: SocialSignInModel(env: env, note: note))
            },
            named: "login-note", configs: Self.tall, layout: .screen)
    }

    func test_changePasswordForced() async {
        let env = AppEnvironment.fake(user: .sample)
        await assertSnapshots(
            of: { ChangePasswordView(env: env, forced: true) },
            named: "change-forced", configs: Self.tall, layout: .screen)
    }
}
