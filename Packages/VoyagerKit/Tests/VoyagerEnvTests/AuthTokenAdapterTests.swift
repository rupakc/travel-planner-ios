import AuthCore
import Foundation
import Testing
import TestSupport
import VoyagerEnv

@MainActor
@Suite struct AuthTokenAdapterTests {
    @Test func test_staleTokenIgnored() async {
        let auth = AuthState(api: FakeAuthAPI(), store: InMemorySessionStore(.sample(token: "new")))
        let adapter = AuthTokenAdapter(auth: auth)
        #expect(await adapter.currentToken() == "new")

        // A late 401 for the previous token: nothing happens, no retry.
        #expect(await adapter.unauthorized(token: "old") == false)
        #expect(auth.phase == .signedIn)
        #expect(auth.session?.accessToken == "new")

        // A 401 for the current token (no refresher): signed out as expired, no retry.
        #expect(await adapter.unauthorized(token: "new") == false)
        #expect(auth.phase == .signedOut(reason: .sessionExpired))
        #expect(await adapter.currentToken() == nil)
    }
}
