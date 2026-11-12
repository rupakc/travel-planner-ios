import Foundation
import Testing
import VoyagerModel

@testable import AppShell

@Suite struct DeepLinksTests {
    private let hosts: Set<String> = ["voyager.example"]

    private func route(_ text: String) -> Route? {
        URL(string: text).flatMap { DeepLinks.route(for: $0, trustedHosts: hosts) }
    }

    @Test func test_shareViaScheme() {
        #expect(route("voyager://share/abc123_-XY") == .share(token: "abc123_-XY"))
    }

    @Test func test_shareViaTrustedHttps() {
        #expect(route("https://voyager.example/share/tok") == .share(token: "tok"))
        #expect(route("https://VOYAGER.example/share/tok") == .share(token: "tok"))
    }

    @Test func test_untrustedHostIsNil() {
        #expect(route("https://evil.example/share/tok") == nil)
        #expect(route("http://voyager.example/share/tok") == nil)
    }

    @Test func test_malformedShareIsNil() {
        #expect(route("voyager://share") == nil)
        #expect(route("voyager://share/a/b") == nil)
        #expect(route("voyager://share/bad%20token") == nil)
    }

    @Test func test_alertLinks() {
        #expect(route("https://voyager.example/alerts?watch=7") == .alerts(kind: nil, watchID: 7))
        #expect(route("https://voyager.example/alerts?kind=hotel&watch=7") == .alerts(kind: .hotel, watchID: 7))
        #expect(route("voyager://alerts?kind=flight&watch=12") == .alerts(kind: .flight, watchID: 12))
        #expect(route("https://voyager.example/alerts?kind=boat&watch=7") == nil)
        #expect(route("https://voyager.example/alerts?watch=abc") == nil)
    }

    @Test func test_importLink() throws {
        let target = try #require(URL(string: "https://example.com/blog/rome"))
        #expect(route("voyager://import?url=https%3A%2F%2Fexample.com%2Fblog%2Frome") == .importLink(target))
        #expect(route("voyager://import?url=javascript%3Aalert(1)") == nil)
        #expect(route("https://voyager.example/import?url=https%3A%2F%2Fexample.com") == nil)
    }

    @Test func test_otherLinksAreNil() {
        #expect(route("voyager://unknown/x") == nil)
        #expect(route("ftp://voyager.example/share/tok") == nil)
        #expect(route("https://voyager.example/") == nil)
    }
}
