import Foundation
import Testing
@testable import AuthCore

@MainActor
struct AuthStateTests {
    private func make(_ api: FakeAPI = FakeAPI(), store: MemoryStore = MemoryStore()) -> (AuthState, FakeAPI, MemoryStore) {
        (AuthState(api: api, store: store), api, store)
    }

    @Test func test_signInStoresSession() async throws {
        let (auth, _, store) = make()
        try await auth.signIn(username: "amy", password: "pw")
        #expect(auth.phase == .signedIn)
        #expect(auth.session?.accessToken == "tok1")
        #expect(auth.session?.method == .password)
        #expect(store.load()?.accessToken == "tok1")
        #expect(auth.tokenSnapshot() == "tok1")
    }

    @Test func test_requiresPasswordChangePhase() async throws {
        let api = FakeAPI()
        api.loginResult = LoginResponse(accessToken: "t", user: User(username: "a", requiresPasswordChange: true))
        let (auth, _, _) = make(api)
        try await auth.signIn(username: "a", password: "x")
        #expect(auth.phase == .needsPasswordChange)
    }

    @Test func test_changePasswordReplacesToken() async throws {
        let api = FakeAPI()
        api.loginResult = LoginResponse(accessToken: "t", user: User(username: "a", requiresPasswordChange: true))
        let (auth, _, store) = make(api)
        try await auth.signIn(username: "a", password: "x")
        try await auth.changePassword(current: "x", new: "newpassword")
        #expect(auth.session?.accessToken == "tok2")
        #expect(auth.session?.user.requiresPasswordChange == false)
        #expect(auth.phase == .signedIn)
        #expect(store.load()?.accessToken == "tok2")
        #expect(auth.tokenSnapshot() == "tok2")
    }

    @Test func test_signOutClears() async throws {
        let (auth, _, store) = make()
        try await auth.signIn(username: "amy", password: "pw")
        await auth.signOut()
        #expect(auth.session == nil)
        #expect(store.load() == nil)
        #expect(auth.phase == .signedOut(reason: .userInitiated))
        #expect(auth.tokenSnapshot() == nil)
    }

    @Test func test_unauthorizedForCurrentTokenExpires() async throws {
        let (auth, _, store) = make()
        try await auth.signIn(username: "amy", password: "pw")
        await auth.handleUnauthorized(token: "tok1")
        #expect(auth.phase == .signedOut(reason: .sessionExpired))
        #expect(store.load() == nil)
    }

    @Test func test_unauthorizedForStaleTokenIgnored() async throws {
        let (auth, _, _) = make()
        try await auth.signIn(username: "amy", password: "pw")
        await auth.handleUnauthorized(token: "old-token")
        #expect(auth.phase == .signedIn)
        #expect(auth.session?.accessToken == "tok1")
    }

    @Test func test_socialComingSoon() async throws {
        let (auth, _, _) = make()
        try await auth.signIn(username: "amy", password: "pw")
        let before = auth.session
        await #expect(throws: AuthError.comingSoon(.google)) {
            try await auth.signIn(with: .google, info: AuthProviderInfo(id: .google, configured: false))
        }
        // A configured provider with the default social handler also refuses.
        await #expect(throws: AuthError.comingSoon(.google)) {
            try await auth.signIn(with: .google, info: AuthProviderInfo(id: .google, configured: true))
        }
        #expect(auth.session == before)
    }

    @Test func test_launchRestoresStoredSession() {
        let s = Session(accessToken: "x", user: User(username: "u"), method: .password)
        let auth = AuthState(api: FakeAPI(), store: MemoryStore(s))
        #expect(auth.phase == .signedIn)
        #expect(auth.tokenSnapshot() == "x")
    }

    @Test func test_loginResponseDecoding() throws {
        let json = #"{"access_token":"eyJ","token_type":"bearer","user":{"username":"admin","is_admin":true,"requires_password_change":false,"email":null}}"#
        let r = try JSONDecoder().decode(LoginResponse.self, from: Data(json.utf8))
        #expect(r.accessToken == "eyJ")
        #expect(r.tokenType == "bearer")
        #expect(r.user == User(username: "admin", isAdmin: true, requiresPasswordChange: false, email: nil))
    }

    @Test func test_jwtExpiryRead() {
        let jwt = "e30." + Data(#"{"exp":1800000000}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "") + ".sig"
        #expect(Session(accessToken: jwt, user: User(username: "u"), method: .password).accessExpiresAt
            == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func test_capabilitiesFromFeatures() {
        #expect(AccountCapabilities.from(features: nil) == .none)
        let c = AccountCapabilities.from(features: ["signup": true, "refresh_tokens": true])
        #expect(c == AccountCapabilities(signUp: true, passwordReset: false, deleteAccount: false, refreshTokens: true))
    }
}
