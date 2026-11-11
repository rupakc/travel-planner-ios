import Foundation
import os
@testable import Telemetry
import VoyagerModel

final class ManualClock: Sendable {
    private let time = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))
    func now() -> Date { time.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { time.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

final class FakeTransport: TelemetryTransport, Sendable {
    struct Post: Sendable {
        var url: URL
        var body: Data
        var gzipped: Bool
        var token: String?

        /// The JSON body, gunzipped when needed.
        var json: [String: Any] {
            var data = body
            if gzipped, let inflated = try? (data.dropFirst(10).dropLast(8) as NSData).decompressed(using: .zlib) {
                data = inflated as Data
            }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }

        var events: [[String: Any]] { json["events"] as? [[String: Any]] ?? [] }
        var names: [String] { events.compactMap { $0["event"] as? String } }
    }

    private struct State: Sendable {
        var posts: [Post] = []
        var script: [TransportOutcome] = []
        var fallback: TransportOutcome = .ok
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(fallback: TransportOutcome = .ok) {
        state.withLock { $0.fallback = fallback }
    }

    var posts: [Post] { state.withLock { $0.posts } }
    func script(_ outcomes: TransportOutcome...) { state.withLock { $0.script = outcomes } }
    func setFallback(_ outcome: TransportOutcome) { state.withLock { $0.fallback = outcome } }

    func post(_ url: URL, body: Data, gzipped: Bool, token: String?) async -> TransportOutcome {
        state.withLock { state in
            state.posts.append(Post(url: url, body: body, gzipped: gzipped, token: token))
            return state.script.isEmpty ? state.fallback : state.script.removeFirst()
        }
    }
}

struct Harness {
    let core: TelemetryCore
    let clock: ManualClock
    let transport: FakeTransport
    let directory: URL
    let defaults: UserDefaults

    static func make(
        remote: TelemetryRemoteConfig? = TelemetryRemoteConfig(),
        transport: FakeTransport = FakeTransport(),
        timeZone: String = "America/New_York",
        endpoint: URL? = URL(string: "https://example.test/api/telemetry"),
        directory: URL? = nil,
        defaults: UserDefaults? = nil,
        clock: ManualClock = ManualClock(),
        token: @escaping @Sendable () async -> String? = { "tok" }
    ) -> Harness {
        let dir = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("telemetry-\(UUID().uuidString)")
        let suite = defaults ?? UserDefaults(suiteName: "telemetry-tests-\(UUID().uuidString)") ?? .standard
        let boot = TelemetryBootstrap(
            appVersion: "1.0.0",
            locale: { "en" },
            endpoint: { endpoint },
            token: token,
            remote: remote,
            storeDirectory: dir,
            now: { clock.now() },
            timeZone: { TimeZone(identifier: timeZone) ?? .gmt },
            transport: transport
        )
        return Harness(
            core: TelemetryCore(boot, defaults: suite, background: false),
            clock: clock, transport: transport, directory: dir, defaults: suite
        )
    }

    var queueFile: URL { directory.appendingPathComponent("tq.json") }
    var queuedNames: [String] { core.queuedEvents().map(\.event) }

    func trackTaps(_ count: Int) {
        for index in 0..<count { core.track(.screenTime(route: "/a", ms: index)) }
    }
}
