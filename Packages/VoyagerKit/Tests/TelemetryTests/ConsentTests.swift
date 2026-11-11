import Foundation
import Testing
@testable import Telemetry

@Suite struct ConsentTests {
    @Test func test_euZones() {
        #expect(Consent.required(timeZone: "Europe/Berlin"))
        #expect(Consent.required(timeZone: "Europe/London"))
        #expect(!Consent.required(timeZone: "Europe/Istanbul"))
        #expect(!Consent.required(timeZone: "Europe/Moscow"))
        #expect(!Consent.required(timeZone: "Europe/Minsk"))
        #expect(!Consent.required(timeZone: "Europe/Kyiv"))
        #expect(!Consent.required(timeZone: "Europe/Kiev"))
        #expect(Consent.required(timeZone: "Atlantic/Canary"))
        #expect(Consent.required(timeZone: "Atlantic/Reykjavik"))
        #expect(!Consent.required(timeZone: "Atlantic/Bermuda"))
        #expect(!Consent.required(timeZone: "America/New_York"))
        #expect(!Consent.required(timeZone: ""))
    }

    @Test func test_onByDefaultOutsideEurope() {
        let h = Harness.make(timeZone: "America/New_York")
        h.core.track(.appOpen)
        #expect(h.queuedNames == ["app_open"])
    }

    @Test func test_nothingQueuedInEuropeUntilChoice() {
        let h = Harness.make(timeZone: "Europe/Berlin")
        h.core.track(.appOpen)
        #expect(h.queuedNames.isEmpty)
    }

    @Test func test_denialClearsQueueAndSendsNothing() async {
        let h = Harness.make(timeZone: "America/New_York")
        h.trackTaps(5)
        h.core.setConsent(false)
        await h.core.settle()
        #expect(h.queuedNames.isEmpty)
        h.core.track(.appOpen)
        await h.core.flushNow()
        await h.core.tick()
        #expect(h.transport.posts.isEmpty)
        #expect(h.queuedNames.isEmpty)
        #expect(Consent.stored(h.defaults) == .denied)
    }

    @Test func test_grantSendsConsentEvent() async {
        let h = Harness.make(timeZone: "Europe/Berlin")
        h.core.setConsent(true)
        await h.core.settle()
        await h.core.flushNow()
        let post = h.transport.posts.first
        #expect(post?.names.contains("consent") == true)
        let consent = post?.events.first { $0["event"] as? String == "consent" }
        #expect((consent?["props"] as? [String: String]) == ["choice": "granted"])
        #expect(Consent.stored(h.defaults) == .granted)
    }

    @Test func test_denialAlsoRemovesPersistedFile() async {
        let h = Harness.make(endpoint: nil)
        h.trackTaps(2)
        await h.core.didEnterBackground()
        #expect(FileManager.default.fileExists(atPath: h.queueFile.path))
        h.core.setConsent(false)
        await h.core.settle()
        #expect(!FileManager.default.fileExists(atPath: h.queueFile.path))
    }
}
