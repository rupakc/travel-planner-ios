import Foundation
import os
import Testing
@testable import Telemetry

@Suite struct PreConfigureTests {
    static func bootstrap(remote: TelemetryRemoteConfig?, timeZone: String = "America/New_York") -> TelemetryBootstrap {
        TelemetryBootstrap(
            appVersion: "1.0.0", locale: { "en" }, endpoint: { nil }, token: { nil }, remote: remote,
            storeDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("pre-\(UUID().uuidString)"),
            timeZone: { TimeZone(identifier: timeZone) ?? .gmt }, transport: FakeTransport()
        )
    }

    static func suite() -> UserDefaults {
        UserDefaults(suiteName: "pre-\(UUID().uuidString)") ?? .standard
    }

    @Test func test_heldEventsDrainWhenEnabled() {
        let telemetry = Telemetry()
        telemetry.track(.perf(metric: .coldStart, value: 250, route: "/"))
        telemetry.track(.screenView(route: "/", referrer: nil))
        #expect(telemetry.heldCount == 2)
        telemetry.configure(Self.bootstrap(remote: TelemetryRemoteConfig()), defaults: Self.suite(), background: false)
        #expect(telemetry.heldCount == 0)
        #expect(telemetry.core?.queuedEvents().map(\.event) == ["perf", "screen_view", "app_open"])
    }

    @Test func test_heldEventsDiscardedWhenDisabled() {
        let off = Telemetry()
        off.track(.appOpen)
        off.configure(Self.bootstrap(remote: nil), defaults: Self.suite(), background: false)
        #expect(off.heldCount == 0)
        #expect(off.core?.queuedEvents().isEmpty == true)

        let eu = Telemetry()
        eu.track(.appOpen)
        eu.configure(
            Self.bootstrap(remote: TelemetryRemoteConfig(), timeZone: "Europe/Berlin"),
            defaults: Self.suite(), background: false
        )
        #expect(eu.core?.queuedEvents().isEmpty == true)
    }

    @Test func test_holdingBufferIsCappedAt50() {
        let telemetry = Telemetry()
        for _ in 0..<80 { telemetry.track(.appOpen) }
        #expect(telemetry.heldCount == 50)
    }

    @Test func test_coldStartIsSpentOnlyWhenAccepted() {
        let held = Telemetry()
        let flag = OSAllocatedUnfairLock(initialState: false)
        ColdStart.mark(into: held, flag: flag)
        #expect(flag.withLock { $0 })
        ColdStart.mark(into: held, flag: flag)
        #expect(held.heldCount == 1)

        let off = Telemetry()
        off.configure(Self.bootstrap(remote: nil), defaults: Self.suite(), background: false)
        let unspent = OSAllocatedUnfairLock(initialState: false)
        ColdStart.mark(into: off, flag: unspent)
        #expect(!unspent.withLock { $0 })
    }

    @Test func test_grantEmitsConsentEvenWhenNotRequired() async {
        let h = Harness.make(timeZone: "America/New_York")
        h.core.setConsent(true)
        await h.core.settle()
        #expect(h.queuedNames == ["consent"])
        h.core.setConsent(true)
        #expect(h.queuedNames == ["consent"])
    }

    @Test func test_batchInFlightWhenConsentDeniedIsNotPosted() async {
        let box = OSAllocatedUnfairLock<TelemetryCore?>(initialState: nil)
        let h = Harness.make(token: {
            box.withLock { $0 }?.setConsent(false)
            return "tok"
        })
        let core = h.core
        box.withLock { $0 = core }
        h.trackTaps(3)
        await h.core.flushNow()
        #expect(h.transport.posts.isEmpty)
        #expect(h.queuedNames.isEmpty)
    }

    @Test func test_screenTrackerDoesNotDuplicateVisibleRoute() async {
        let telemetry = Telemetry()
        telemetry.configure(Self.bootstrap(remote: TelemetryRemoteConfig()), defaults: Self.suite(), background: false)
        let tracker = ScreenTracker(telemetry: telemetry, now: { Date() })
        tracker.appeared("/chat")
        tracker.appeared("/chat")
        let views = telemetry.core?.queuedEvents().filter { $0.event == "screen_view" } ?? []
        #expect(views.count == 1)
    }
}
