import Foundation
import Testing

@testable import FeatureShare

struct ShareLinkParserTests {
    private let hosts: Set<String> = ["voyager.example"]

    @Test func test_acceptsOurLinks() {
        #expect(ShareLinkParser.token(from: URL(string: "https://voyager.example/share/Abc_123-xyz")!, trustedHosts: hosts) == "Abc_123-xyz")
        #expect(ShareLinkParser.token(from: URL(string: "https://VOYAGER.example/share/Abc_123-xyz?utm=1")!, trustedHosts: hosts) == "Abc_123-xyz")
        #expect(ShareLinkParser.token(from: URL(string: "voyager://share/Abc_123-xyz")!, trustedHosts: hosts) == "Abc_123-xyz")
    }

    @Test func test_refusesTheRest() {
        for text in [
            "https://other.example/share/Abc_123-xyz", "http://voyager.example/share/Abc_123-xyz", "ftp://voyager.example/share/Abc_123-xyz",
            "https://voyager.example/share/", "https://voyager.example/share/short", "https://voyager.example/share/Abc_123-xyz/page",
            "https://voyager.example/api/share/Abc_123-xyz", "voyager://trips/12345678",
        ] {
            #expect(ShareLinkParser.token(from: URL(string: text)!, trustedHosts: hosts) == nil, "\(text)")
        }
    }

    @Test func test_serverURLsGiveTheirToken() {
        #expect(ShareLinkParser.token(fromServerURL: "https://voyager.example/share/legacytok7") == "legacytok7")
        #expect(ShareLinkParser.token(fromServerURL: "https://voyager.example/app/share/legacytok7") == "legacytok7")
        #expect(ShareLinkParser.token(fromServerURL: "https://voyager.example/") == nil)
        #expect(ShareLinkParser.token(fromServerURL: "not a url") == nil)
    }
}
