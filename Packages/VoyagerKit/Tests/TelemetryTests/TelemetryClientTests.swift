import Foundation
import Testing
@testable import Telemetry
import VoyagerModel

@Suite struct TelemetryClientTests {
    @Test func test_disabledWhenRemoteNil() async {
        let h = Harness.make(remote: nil)
        h.core.start()
        h.trackTaps(60)
        await h.core.settle()
        await h.core.flushNow()
        #expect(h.queuedNames.isEmpty)
        #expect(h.transport.posts.isEmpty)
    }

    @Test func test_disabledWhenRemoteSaysSo() async {
        let h = Harness.make(remote: TelemetryRemoteConfig(enabled: false))
        h.trackTaps(60)
        await h.core.settle()
        #expect(h.transport.posts.isEmpty)
    }

    @Test func test_404DisablesForSessionNoRetry() async {
        let h = Harness.make(transport: FakeTransport(fallback: .disabled))
        h.trackTaps(3)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 1)
        h.trackTaps(60)
        h.clock.advance(3600)
        await h.core.settle()
        await h.core.flushNow()
        await h.core.tick()
        #expect(h.transport.posts.count == 1)
        #expect(h.queuedNames.isEmpty)
    }

    @Test func test_flushAt50() async {
        let h = Harness.make()
        h.trackTaps(49)
        await h.core.settle()
        #expect(h.transport.posts.isEmpty)
        h.trackTaps(1)
        await h.core.settle()
        #expect(h.transport.posts.count == 1)
        #expect(h.transport.posts.first?.events.count == 50)
        #expect(h.queuedNames.isEmpty)
    }

    @Test func test_maxBatchIsClampedTo100() async {
        let h = Harness.make(remote: TelemetryRemoteConfig(maxBatch: 5_000))
        h.trackTaps(100)
        await h.core.settle()
        #expect(h.transport.posts.first?.events.count == 100)
    }

    @Test func test_flushEvery15s() async {
        let h = Harness.make()
        h.trackTaps(3)
        h.clock.advance(14)
        await h.core.tick()
        #expect(h.transport.posts.isEmpty)
        h.clock.advance(1)
        await h.core.tick()
        #expect(h.transport.posts.count == 1)
        #expect(h.transport.posts.first?.events.count == 3)
    }

    @Test func test_postCarriesEnvelopeAndToken() async {
        let h = Harness.make()
        h.core.track(.uiTap(tid: "search.submit", route: "/"))
        await h.core.flushNow()
        let post = h.transport.posts.first
        let client = post?.json["client"] as? [String: String]
        #expect(client?["platform"] == "ios")
        #expect(client?["app_version"] == "1.0.0")
        #expect(client?["locale"] == "en")
        #expect(UUID(uuidString: client?["anon_id"] ?? "") != nil)
        #expect(UUID(uuidString: client?["session_id"] ?? "") != nil)
        #expect(post?.token == "tok")
        #expect(post?.events.first?["screen"] as? String == "/")
        #expect(h.defaults.string(forKey: "tp_anon") == client?["anon_id"])
    }

    @Test func test_bodiesOver1KBAreGzipped() async {
        let h = Harness.make()
        for index in 0..<50 { h.core.track(.uiTap(tid: "some.longer.control.id.\(index)", route: "/search/results")) }
        await h.core.settle()
        let post = h.transport.posts.first
        #expect(post?.gzipped == true)
        #expect(post?.events.count == 50)
        let small = Harness.make()
        small.core.track(.appOpen)
        await small.core.flushNow()
        #expect(small.transport.posts.first?.gzipped == false)
    }

    @Test func test_backoffAfterThreeFailures() async {
        let h = Harness.make(transport: FakeTransport(fallback: .failed))
        h.trackTaps(2)
        await h.core.flushNow()
        await h.core.flushNow()
        await h.core.flushNow()
        #expect(h.transport.posts.count == 3)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 3)
        h.clock.advance(29)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 3)
        h.clock.advance(1)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 4)
        // The next failure doubles the wait to 60 s.
        h.clock.advance(59)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 4)
        h.clock.advance(1)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 5)
        #expect(h.core.queuedEvents().count == 2)
    }

    @Test func test_retryAfterHonoured() async {
        let h = Harness.make()
        h.transport.script(.retryAfter(120))
        h.trackTaps(2)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 1)
        h.clock.advance(119)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 1)
        h.clock.advance(1)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 2)
        #expect(h.queuedNames.isEmpty)
    }

    @Test func test_400DropsBatch() async {
        let h = Harness.make(transport: FakeTransport(fallback: .drop))
        h.trackTaps(4)
        await h.core.flushNow()
        #expect(h.transport.posts.count == 1)
        #expect(h.queuedNames.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: h.queueFile.path))
        await h.core.flushNow()
        #expect(h.transport.posts.count == 1)
    }

    @Test func test_sessionRollsAfter30MinIdle() async {
        let h = Harness.make()
        h.core.track(.appOpen)
        h.clock.advance(29 * 60)
        h.core.track(.appOpen)
        #expect(!h.queuedNames.contains("session_start"))
        h.clock.advance(31 * 60)
        h.core.track(.appOpen)
        #expect(h.queuedNames == ["app_open", "app_open", "session_start", "app_open"])
        let sessions = Set(h.core.queuedEvents().map(\.session))
        #expect(sessions.count == 2)
        await h.core.flushNow()
        // One session per batch: the two sessions go out as two posts.
        await h.core.flushNow()
        #expect(h.transport.posts.count == 2)
        #expect(h.transport.posts.last?.names == ["session_start", "app_open"])
    }

    @Test func test_startEmitsAppOpenWhenAllowed() async {
        let h = Harness.make()
        h.core.start()
        await h.core.settle()
        #expect(h.queuedNames == ["app_open"])
        let eu = Harness.make(timeZone: "Europe/Paris")
        eu.core.start()
        await eu.core.settle()
        #expect(eu.queuedNames.isEmpty)
    }

    @Test func test_trackIsCheap() async {
        // Best of three timed loops: runner noise is not cost.
        let clock = ContinuousClock()
        var best = Double.infinity
        for _ in 0..<3 {
            let h = Harness.make()
            let elapsed = clock.measure {
                for _ in 0..<10_000 { h.core.track(.uiTap(tid: "search.submit", route: "/")) }
            }
            best = min(best, Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
            await h.core.settle()
        }
        print("test_trackIsCheap: best of 3, 10 000 tracks in \(best) ms")
        #expect(best < 50, "10 000 tracks took \(best) ms (best of 3)")
    }
}

@Suite struct TransportMappingTests {
    @Test func test_statusMapping() {
        typealias T = URLSessionTelemetryTransport
        #expect(T.outcome(status: 204, retryAfter: nil) == .ok)
        #expect(T.outcome(status: 404, retryAfter: nil) == .disabled)
        #expect(T.outcome(status: 429, retryAfter: "30") == .retryAfter(30))
        #expect(T.outcome(status: 429, retryAfter: nil) == .retryAfter(60))
        #expect(T.outcome(status: 400, retryAfter: nil) == .drop)
        #expect(T.outcome(status: 422, retryAfter: nil) == .drop)
        #expect(T.outcome(status: 413, retryAfter: nil) == .drop)
        #expect(T.outcome(status: 408, retryAfter: nil) == .failed)
        #expect(T.outcome(status: 503, retryAfter: nil) == .failed)
    }
}
