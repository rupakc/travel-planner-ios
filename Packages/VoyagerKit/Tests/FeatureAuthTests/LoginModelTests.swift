import AuthCore
import L10n
import Networking
import TestSupport
import VoyagerEnv
import XCTest

@testable import FeatureAuth

@MainActor
final class LoginModelTests: XCTestCase {
    private func model(_ script: (FakeAuthAPI) -> Void = { _ in }) -> (LoginModel, AppEnvironment, FakeAuthAPI) {
        let fakes = FakeRepositories()
        script(fakes.auth)
        let env = AppEnvironment.fake(user: nil, fakes: fakes)
        return (LoginModel(env: env), env, fakes.auth)
    }

    func test_invalidCredentialsCopy() async {
        let (login, env, _) = model { $0.onLogin.fails(APIError.unauthorized) }
        login.username = "amy"
        login.password = "wrong"
        await login.submit()
        XCTAssertEqual(login.error, L10n.text(K.account.login.failed))
        XCTAssertEqual(env.auth.phase, .signedOut(reason: nil))
        XCTAssertFalse(login.isBusy)
    }

    func test_rateLimitShowsBackendString() async {
        let text = "Too many login attempts. Try again in 5 minutes."
        let (login, _, _) = model { $0.onLogin.fails(APIError.rateLimited(message: text, retryAfter: 300)) }
        login.username = "amy"
        login.password = "pw"
        await login.submit()
        XCTAssertEqual(login.error, text)
    }

    func test_submitDisabledWhenEmpty() {
        let (login, _, _) = model()
        XCTAssertFalse(login.canSubmit)
        login.username = "amy"
        XCTAssertFalse(login.canSubmit)
        login.password = "pw"
        XCTAssertTrue(login.canSubmit)
        login.username = "   "
        XCTAssertFalse(login.canSubmit)
    }

    func test_successSignsInAndClearsPassword() async {
        let (login, env, api) = model()
        login.username = "amy"
        login.password = "pw"
        await login.submit()
        XCTAssertNil(login.error)
        XCTAssertEqual(env.auth.phase, .signedIn)
        XCTAssertEqual(api.onLogin.lastCall?.username, "amy")
        XCTAssertEqual(login.password, "")
    }
}

@MainActor
final class ChangePasswordModelTests: XCTestCase {
    private func make() -> (ChangePasswordModel, AppEnvironment, FakeAuthAPI) {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes)
        return (ChangePasswordModel(env: env), env, fakes.auth)
    }

    func test_tooShortAndMismatch() async {
        let (model, _, api) = make()
        model.current = "old"
        model.new = "short"
        model.confirm = "short"
        await model.submit()
        XCTAssertEqual(model.error, L10n.text(K.account.changePassword.tooShort))
        model.new = "longenough1"
        model.confirm = "different1"
        await model.submit()
        XCTAssertEqual(model.error, L10n.text(K.account.changePassword.mismatch))
        XCTAssertEqual(api.onChangePassword.callCount, 0)
    }

    func test_successReplacesToken() async {
        let (model, env, api) = make()
        model.current = "old"
        model.new = "longenough1"
        model.confirm = "longenough1"
        await model.submit()
        XCTAssertNil(model.error)
        XCTAssertTrue(model.didSucceed)
        XCTAssertEqual(api.onChangePassword.lastCall?.new, "longenough1")
        XCTAssertEqual(env.auth.session?.accessToken, "fake-token-changed")
    }

    func test_serverDetailShown() async {
        let (model, _, api) = make()
        api.onChangePassword.fails(APIError.client(status: 400, detail: "Current password is wrong", code: nil, body: .null))
        model.current = "old"
        model.new = "longenough1"
        model.confirm = "longenough1"
        await model.submit()
        XCTAssertEqual(model.error, "Current password is wrong")
    }
}
