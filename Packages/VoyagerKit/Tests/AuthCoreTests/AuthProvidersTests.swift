import Testing
@testable import AuthCore

struct AuthProvidersTests {
    @Test func test_404MeansAllUnconfigured() async {
        let api = FakeAPI()
        api.providerResult = .failure(NotFound())
        let p = await AuthProviderCatalog(api: api).providers()
        #expect(p.count == 4)
        #expect(p.values.allSatisfy { !$0.configured })
    }

    @Test func test_listMerged() async {
        let api = FakeAPI()
        api.providerResult = .success([AuthProviderInfo(id: .google, configured: true)])
        let p = await AuthProviderCatalog(api: api).providers()
        #expect(p[.google]?.configured == true)
        #expect(p[.apple]?.configured == false)
        #expect(p[.facebook]?.configured == false)
        #expect(p[.github]?.configured == false)
    }

    @Test func test_cachedNoSecondCall() async {
        let api = FakeAPI()
        api.providerResult = .failure(NotFound())
        let c = AuthProviderCatalog(api: api)
        _ = await c.providers()
        _ = await c.providers()
        #expect(api.providerCalls == 1)
    }

    @Test func test_displayOrderAndNames() {
        #expect(AuthProviderID.allCases.map(\.displayName) == ["Apple", "Google", "Facebook", "GitHub"])
    }
}
