import Foundation
import os
import VoyagerModel

/// Everything shared between the synchronous `track` path and the sender.
final class TelemetryShared: Sendable {
    struct State: Sendable {
        var allowed: Bool
        var enabled: Bool
        var buffer = EventBuffer()
        var session: SessionClock
        var maxBatch: Int
        var flushInterval: TimeInterval
        var flushScheduled = false
        var nextTriggerAfter = Date.distantPast
        var timerActive = false
        var retained: [Task<Void, Never>] = []
    }

    let boot: TelemetryBootstrap
    // UserDefaults is thread-safe; the SDK just does not mark it Sendable.
    nonisolated(unsafe) let defaults: UserDefaults
    let store: QueueStore
    let state: OSAllocatedUnfairLock<State>
    let queue = DispatchSerialQueue(label: "io.github.rupakc.travelplanner.telemetry", qos: .utility)

    init(_ boot: TelemetryBootstrap, defaults: UserDefaults) {
        self.boot = boot
        self.defaults = defaults
        store = QueueStore(directory: boot.storeDirectory)
        let remote = boot.remote
        let now = boot.now()
        state = OSAllocatedUnfairLock(initialState: State(
            allowed: Consent.allowed(defaults: defaults, timeZone: boot.timeZone().identifier),
            enabled: remote?.enabled == true,
            session: SessionClock(now: now),
            maxBatch: min(max(remote?.maxBatch ?? 50, 1), 100),
            flushInterval: TimeInterval(max(remote?.flushIntervalS ?? 15, 1))
        ))
    }
}

/// The engine behind `Telemetry`. Internal so tests can drive it with a manual clock and a fake transport.
final class TelemetryCore: Sendable {
    static let timerPeriod: Duration = .seconds(5)
    static let triggerThrottle: TimeInterval = 1

    let shared: TelemetryShared
    private let sender: TelemetrySender
    /// Tests: keep spawned tasks so `settle()` can await them, and do not run the real timer.
    private let background: Bool

    init(_ boot: TelemetryBootstrap, defaults: UserDefaults, background: Bool) {
        shared = TelemetryShared(boot, defaults: defaults)
        sender = TelemetrySender(shared)
        self.background = background
    }

    var zoneIdentifier: String { shared.boot.timeZone().identifier }

    // MARK: Lifecycle

    /// Starts collection when the remote config and consent allow it. Returns immediately; file work is deferred.
    func start() {
        let active = shared.state.withLock { $0.enabled && $0.allowed }
        guard active else { return }
        track(.appOpen)
        spawn { await self.sender.claimPersisted() }
        if background { startTimerIfNeeded() }
    }

    private func startTimerIfNeeded() {
        let needed = shared.state.withLock { state -> Bool in
            guard !state.timerActive else { return false }
            state.timerActive = true
            return true
        }
        if needed { Task.detached(priority: .utility) { await self.sender.startTimer() } }
    }

    private func spawn(_ work: @escaping @Sendable () async -> Void) {
        let task = Task.detached(priority: .utility, operation: work)
        if !background { shared.state.withLock { $0.retained.append(task) } }
    }

    // MARK: Tracking

    func track(_ event: TelemetryEvent) {
        let wire = event.wire
        let now = shared.boot.now()
        let action: (flush: Bool, timer: Bool) = shared.state.withLock { state in
            guard state.allowed, state.enabled else { return (false, false) }
            let rolled = state.session.touch(now: now)
            let ts = Int64(now.timeIntervalSince1970 * 1000)
            if rolled {
                state.buffer.append(StoredEvent(event: "session_start", ts: ts, screen: nil, props: [:], session: state.session.id))
            }
            state.buffer.append(StoredEvent(event: wire.name, ts: ts, screen: wire.screen, props: wire.props, session: state.session.id))
            var flush = false
            if state.buffer.count >= state.maxBatch, !state.flushScheduled, now >= state.nextTriggerAfter {
                state.flushScheduled = true
                state.nextTriggerAfter = now.addingTimeInterval(Self.triggerThrottle)
                flush = true
            }
            return (flush, background && !state.timerActive)
        }
        if action.flush {
            spawn {
                await self.sender.flush(force: true)
                self.shared.state.withLock { $0.flushScheduled = false }
            }
        }
        if action.timer { startTimerIfNeeded() }
    }

    func setConsent(_ granted: Bool) {
        Consent.store(granted ? .granted : .denied, in: shared.defaults)
        let allowed = Consent.allowed(defaults: shared.defaults, timeZone: zoneIdentifier)
        let wasAllowed = shared.state.withLock { state -> Bool in
            defer { state.allowed = allowed }
            return state.allowed
        }
        if !granted {
            shared.state.withLock { $0.buffer.removeAll() }
            spawn { await self.sender.clearStore() }
        } else if !wasAllowed {
            track(.consentGranted)
            track(.appOpen)
            spawn { await self.sender.claimPersisted() }
            if background { startTimerIfNeeded() }
        }
    }

    func didEnterBackground() async {
        track(.appBackground)
        await sender.flush(force: true, maxBatches: 10)
        await sender.persistRemainder()
        shared.state.withLock { $0.timerActive = false }
        await sender.stopTimer()
    }

    func flushPersisted() async {
        await sender.claimPersisted()
        await sender.flush(force: true, maxBatches: 10)
        await sender.persistRemainder()
    }

    // MARK: Test hooks

    func queuedEvents() -> [StoredEvent] { shared.state.withLock { $0.buffer.all } }
    func tick() async { await sender.flush(force: false) }
    func flushNow() async { await sender.flush(force: true) }

    /// Awaits every task `start`/`track`/`setConsent` spawned (only retained when `background` is false).
    func settle() async {
        while true {
            let tasks = shared.state.withLock { state -> [Task<Void, Never>] in
                defer { state.retained = [] }
                return state.retained
            }
            if tasks.isEmpty { return }
            for task in tasks { await task.value }
        }
    }
}
