import Foundation
import Testing
@testable import Telemetry
import VoyagerModel

@Suite struct TelemetryQueueTests {
    @Test func test_capAt500DropsOldest() {
        let h = Harness.make(endpoint: nil)
        h.trackTaps(600)
        let events = h.core.queuedEvents()
        #expect(events.count == 500)
        #expect(events.first?.props["ms"] == .number(100))
        #expect(events.last?.props["ms"] == .number(599))
    }

    @Test func test_persistOnlyOnBackgroundOrFailure() async {
        // A successful send never writes the file.
        let ok = Harness.make()
        ok.trackTaps(3)
        await ok.core.flushNow()
        #expect(!FileManager.default.fileExists(atPath: ok.queueFile.path))

        // A failed send does.
        let failing = Harness.make(transport: FakeTransport(fallback: .failed))
        failing.trackTaps(3)
        #expect(!FileManager.default.fileExists(atPath: failing.queueFile.path))
        await failing.core.flushNow()
        #expect(FileManager.default.fileExists(atPath: failing.queueFile.path))

        // Background persists what could not be sent, and the next start claims it.
        let offline = Harness.make(endpoint: nil)
        offline.trackTaps(3)
        #expect(!FileManager.default.fileExists(atPath: offline.queueFile.path))
        await offline.core.didEnterBackground()
        #expect(FileManager.default.fileExists(atPath: offline.queueFile.path))
        let next = Harness.make(directory: offline.directory, defaults: offline.defaults)
        next.core.start()
        await next.core.settle()
        #expect(next.queuedNames.count == 5)
        #expect(next.queuedNames.contains("app_background"))
        #expect(!FileManager.default.fileExists(atPath: offline.queueFile.path))
    }

    @Test func test_persistedFileIsRewrittenAfterLaterSuccess() async {
        let h = Harness.make(transport: FakeTransport(fallback: .ok))
        h.transport.script(.failed)
        h.trackTaps(2)
        await h.core.flushNow()
        #expect(FileManager.default.fileExists(atPath: h.queueFile.path))
        await h.core.flushNow()
        #expect(!FileManager.default.fileExists(atPath: h.queueFile.path))
    }

    @Test func test_discardsOlderThan7Days() async {
        let h = Harness.make()
        let nowMs = Int64(h.clock.now().timeIntervalSince1970 * 1000)
        let day: Int64 = 24 * 3600 * 1000
        func stored(_ name: String, _ ts: Int64) -> StoredEvent {
            StoredEvent(event: name, ts: ts, screen: nil, props: [:], session: "s")
        }
        QueueStore(directory: h.directory).save([
            stored("app_open", nowMs - 8 * day), stored("app_background", nowMs - 6 * day),
        ])
        h.core.start()
        await h.core.settle()
                #expect(h.core.queuedEvents().filter { $0.ts == nowMs - 8 * day }.isEmpty)
        #expect(h.core.queuedEvents().filter { $0.ts == nowMs - 6 * day }.count == 1)
    }

    @Test func test_writeFailureSwallowed() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: parent)
        let h = Harness.make(transport: FakeTransport(fallback: .failed), directory: parent.appendingPathComponent("sub"))
        h.trackTaps(3)
        await h.core.flushNow()
        await h.core.didEnterBackground()
        h.core.track(.appOpen)
        #expect(h.queuedNames.contains("app_open"))
        #expect(!FileManager.default.fileExists(atPath: h.queueFile.path))
    }

    @Test func test_writeFailureInReadOnlyDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
        let h = Harness.make(transport: FakeTransport(fallback: .failed), directory: dir)
        h.trackTaps(2)
        await h.core.flushNow()
        h.core.track(.appOpen)
        #expect(h.queuedNames.contains("app_open"))
    }
}
