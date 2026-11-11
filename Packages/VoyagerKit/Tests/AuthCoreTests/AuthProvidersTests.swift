import Foundation
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

    @Test func test_concurrentFirstCallersShareOneRequest() async {
        let api = FakeAPI()
        api.providerDelay = .milliseconds(100)
        api.providerResult = .success([AuthProviderInfo(id: .github, configured: true)])
        let c = AuthProviderCatalog(api: api)
        async let a = c.providers()
        async let b = c.providers()
        let (pa, pb) = await (a, b)
        #expect(api.providerCalls == 1)
        #expect(pa[.github]?.configured == true)
        #expect(pb[.github]?.configured == true)
    }

    @Test func test_successfulListCached() async {
        let api = FakeAPI()
        api.providerResult = .success([AuthProviderInfo(id: .google, configured: true)])
        let c = AuthProviderCatalog(api: api)
        _ = await c.providers()
        let again = await c.providers()
        #expect(api.providerCalls == 1)
        #expect(again[.google]?.configured == true)
    }

    @Test func test_lenientDecodeSkipsUnknownAndBadEntries() throws {
        let json = #"""
        [{"id":"google","configured":true,"start_url":"https://x.io/api/auth/google"},
         {"id":"gitlab","configured":true},
         {"id":"github"},
         {"id":"facebook","configured":false}]
        """#
        let list = try AuthProviderInfo.decodeList(from: Data(json.utf8))
        #expect(list.map(\.id) == [.google, .facebook])
        #expect(list[0].startURL?.absoluteString == "https://x.io/api/auth/google")
        let wrapped = try AuthProviderInfo.decodeList(from: Data(#"{"providers":[{"id":"apple","configured":true},{"id":"zzz","configured":true}]}"#.utf8))
        #expect(wrapped.map(\.id) == [.apple])
    }

    @Test func test_displayOrderAndNames() {
        #expect(AuthProviderID.allCases.map(\.displayName) == ["Apple", "Google", "Facebook", "GitHub"])
    }
}
