import Foundation
import os
import VoyagerModel

/// Does all the I/O: batching, sending, backoff and the offline file. Isolated to the private serial
/// `.utility` dispatch queue.
actor TelemetrySender {
    private let shared: TelemetryShared
    private var failures = 0
    private var backoffUntil = Date.distantPast
    private var lastFlushAt: Date
    private var flushing = false
    private var persistedFile = false
    private var anonID: String?
    private var timer: Task<Void, Never>?

    nonisolated var unownedExecutor: UnownedSerialExecutor { shared.queue.asUnownedSerialExecutor() }

    init(_ shared: TelemetryShared) {
        self.shared = shared
        lastFlushAt = shared.boot.now()
    }

    // MARK: Timer

    func startTimer() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: TelemetryCore.timerPeriod)
                if Task.isCancelled { break }
                await self?.flush(force: false)
            }
        }
    }

    func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: Flushing

    func flush(force: Bool, maxBatches: Int = 1) async {
        guard !flushing else { return }
        let now = shared.boot.now()
        let snapshot = shared.state.withLock { ($0.allowed && $0.enabled, $0.flushInterval, $0.buffer.isEmpty) }
        guard snapshot.0, !snapshot.2, now >= backoffUntil else { return }
        if !force, now.timeIntervalSince(lastFlushAt) < snapshot.1 { return }
        guard let url = shared.boot.endpoint() else { return }
        flushing = true
        defer { flushing = false }
        lastFlushAt = now
        for _ in 0..<maxBatches {
            let batch = shared.state.withLock { $0.buffer.popBatch(limit: $0.maxBatch) }
            if batch.isEmpty { return }
            let outcome = await send(batch, to: url)
            if !handle(outcome, batch: batch) { return }
        }
    }

    private func send(_ batch: [StoredEvent], to url: URL) async -> TransportOutcome {
        let envelope = Envelope(
            anonID: anonymousID(),
            appVersion: Envelope.safeToken(shared.boot.appVersion, fallback: "unknown"),
            locale: Envelope.safeToken(shared.boot.locale(), fallback: "en", limit: 16),
            batch: batch
        )
        guard let body = try? JSONEncoder().encode(envelope) else { return .drop }
        let gzip = body.count > 1024
        let token = await shared.boot.token()
        return await shared.boot.transport.post(
            url, body: gzip ? Gzip.compress(body) : body, gzipped: gzip, token: token
        )
    }

    /// Applies an outcome; returns `true` when the next batch may be sent.
    private func handle(_ outcome: TransportOutcome, batch: [StoredEvent]) -> Bool {
        let now = shared.boot.now()
        let stillAllowed = shared.state.withLock { $0.allowed && $0.enabled }
        switch outcome {
        case .ok:
            failures = 0
            if persistedFile { rewriteFile() }
            return stillAllowed
        case .disabled:
            shared.state.withLock {
                $0.enabled = false
                $0.buffer.removeAll()
            }
            shared.store.clear()
            persistedFile = false
            return false
        case .drop:
            failures = 0
            return stillAllowed
        case .retryAfter(let seconds):
            backoffUntil = now.addingTimeInterval(TimeInterval(seconds))
            requeueAndPersist(batch)
            return false
        case .failed:
            failures += 1
            if failures >= 3 {
                let delay = min(30.0 * pow(2.0, Double(failures - 3)), 1800)
                backoffUntil = now.addingTimeInterval(delay)
            }
            requeueAndPersist(batch)
            return false
        }
    }

    private func requeueAndPersist(_ batch: [StoredEvent]) {
        let events = shared.state.withLock { state -> [StoredEvent]? in
            guard state.allowed, state.enabled else { return nil }
            state.buffer.pushFront(batch)
            return state.buffer.all
        }
        if let events { writeFile(events) }
    }

    // MARK: Offline file

    func persistRemainder() {
        let events = shared.state.withLock { $0.buffer.all }
        if !events.isEmpty { writeFile(events) }
    }

    func claimPersisted() {
        let now = shared.boot.now()
        let events = shared.store.claim(now: now)
        persistedFile = false
        guard !events.isEmpty else { return }
        shared.state.withLock { state in
            guard state.allowed, state.enabled else { return }
            state.buffer.pushFront(events)
        }
    }

    func clearStore() {
        shared.store.clear()
        persistedFile = false
    }

    private func writeFile(_ events: [StoredEvent]) {
        shared.store.save(events)
        persistedFile = shared.store.exists
    }

    /// After a successful send while a file exists: keep the file equal to what is still queued.
    private func rewriteFile() {
        let events = shared.state.withLock { $0.buffer.all }
        if events.isEmpty {
            shared.store.clear()
            persistedFile = false
        } else {
            writeFile(events)
        }
    }

    private func anonymousID() -> String {
        if let anonID { return anonID }
        let key = "tp_anon"
        let id: String
        if let stored = shared.defaults.string(forKey: key), UUID(uuidString: stored) != nil {
            id = stored
        } else {
            id = UUID().uuidString.lowercased()
            shared.defaults.set(id, forKey: key)
        }
        anonID = id
        return id
    }
}
