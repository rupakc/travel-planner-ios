import AuthCore
import L10n
import Networking
import TestSupport
import VoyagerEnv
import XCTest

@testable import FeatureAuth

@MainActor
final class SocialButtonsTests: XCTestCase {
    func test_unconfiguredShowsComingSoonNote() async {
        let env = AppEnvironment.fake(user: nil)
        let model = SocialSignInModel(env: env)
        XCTAssertNil(model.note)
        await model.tap(.google)
        XCTAssertEqual(model.note, L10n.text(K.auth.comingSoon, ["provider": "Google"]))
        XCTAssertEqual(env.auth.phase, .signedOut(reason: nil))
    }

    func test_providers404AllComingSoon() async {
        let fakes = FakeRepositories()
        fakes.auth.onProviders.fails(APIError.notFound(nil))
        let env = AppEnvironment.fake(user: nil, fakes: fakes)
        let model = SocialSignInModel(env: env)
        for provider in AuthProviderID.allCases {
            model.note = nil
            await model.tap(provider)
            XCTAssertEqual(model.note, L10n.text(K.auth.comingSoon, ["provider": provider.displayName]))
        }
    }

    func test_orderAndNames() {
        XCTAssertEqual(AuthProviderID.allCases.map(\.displayName), ["Apple", "Google", "Facebook", "GitHub"])
    }
}
