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

    @Test func test_phase3to6Paths() {
        #expect(route("https://voyager.example/trips/7") == .planDetail(id: 7))
        #expect(route("https://voyager.example/trips/7/today") == .tripToday(planID: 7))
        #expect(route("voyager://trips/7/today") == .tripToday(planID: 7))
        #expect(route("https://voyager.example/feed") == .ideas)
        #expect(route("https://voyager.example/feed/idea_42") == .ideaDetail(id: "idea_42"))
        #expect(route("https://voyager.example/u/amy_x") == .profile(handle: "amy_x"))
        #expect(route("https://voyager.example/play") == .play)
        #expect(route("https://voyager.example/play/h2h/m-1") == .h2h(id: "m-1"))
        #expect(route("https://voyager.example/share/tok") == .share(token: "tok"))
        #expect(route("https://voyager.example/alerts") == .alerts(kind: nil, watchID: nil))
        // Malformed ids and extra segments are nil.
        #expect(route("https://voyager.example/trips/abc") == nil)
        #expect(route("https://voyager.example/trips/0") == nil)
        #expect(route("https://voyager.example/trips/7/tomorrow") == nil)
        #expect(route("https://voyager.example/trips/7/today/x") == nil)
        #expect(route("https://voyager.example/u/bad%20handle") == nil)
        #expect(route("https://voyager.example/feed/a/b") == nil)
        #expect(route("https://voyager.example/play/h2h") == nil)
        #expect(route("https://evil.example/trips/7") == nil)
    }

    @Test func test_notificationLinksMapThroughTheAllowList() {
        func link(_ text: String) -> Route? { DeepLinks.route(forNotificationLink: text) }
        #expect(link("/trips/7") == .planDetail(id: 7))
        #expect(link("/trips/7/today") == .tripToday(planID: 7))
        #expect(link("/feed") == .ideas)
        #expect(link("/feed/42") == .ideaDetail(id: "42"))
        #expect(link("/u/amy") == .profile(handle: "amy"))
        #expect(link("/play/h2h/abc123") == .h2h(id: "abc123"))
        #expect(link("/share/tok") == .share(token: "tok"))
        #expect(link("/alerts") == .alerts(kind: nil, watchID: nil))
        #expect(link("/alerts?kind=hotel&watch=3") == .alerts(kind: .hotel, watchID: 3))
    }

    @Test func test_rawLinkNeverOpened() {
        func link(_ text: String) -> Route? { DeepLinks.route(forNotificationLink: text) }
        for raw in [
            "https://voyager.example/trips/7", "https://evil.example/feed", "//evil.example/feed", "javascript:alert(1)",
            "voyager://trips/7", "trips/7", "", "/", "/unknown", "/trips/abc", "/trips/7/../8", "/feed//x", "/import?url=https%3A%2F%2Fx.example",
            "/feed\\evil", "/trips/7/today/", "/u/",
        ] {
            #expect(link(raw) == nil, "\(raw)")
        }
        #expect(link("/" + String(repeating: "a", count: 300)) == nil)
    }
}
