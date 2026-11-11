import Foundation
import os

/// Thrown by a fake method nobody scripted.
public enum FakeRepositoryError: Error, Equatable, Sendable {
    case notScripted(String)
}

/// One scripted fake method: set `handler` (or call `returns` / `fails`) and read `calls` afterwards.
/// Thread-safe; every call is recorded before the handler runs.
public final class FakeCall<Input: Sendable, Output: Sendable>: Sendable {
    public typealias Handler = @Sendable (Input) async throws -> Output

    private struct State: Sendable {
        var handler: Handler
        var calls: [Input] = []
    }

    public let name: String
    private let state: OSAllocatedUnfairLock<State>

    /// Without a default handler, an unscripted call throws `FakeRepositoryError.notScripted(name)`.
    public init(_ name: String, default handler: Handler? = nil) {
        self.name = name
        let fallback: Handler = handler ?? { _ in throw FakeRepositoryError.notScripted(name) }
        state = OSAllocatedUnfairLock(initialState: State(handler: fallback))
    }

    public var handler: Handler {
        get { state.withLock { $0.handler } }
        set { state.withLock { $0.handler = newValue } }
    }

    public var calls: [Input] { state.withLock { $0.calls } }
    public var callCount: Int { state.withLock { $0.calls.count } }
    public var lastCall: Input? { state.withLock { $0.calls.last } }

    public func returns(_ value: Output) { handler = { _ in value } }
    public func fails(_ error: any Error & Sendable) { handler = { _ in throw error } }

    public func callAsFunction(_ input: Input) async throws -> Output {
        let current = state.withLock { state -> Handler in
            state.calls.append(input)
            return state.handler
        }
        return try await current(input)
    }
}

extension FakeCall where Input == Void {
    public func callAsFunction() async throws -> Output { try await self(()) }
}

/// A scripted streaming method (`search`, `chat`). By default the stream finishes at once with no events.
public final class FakeStreamCall<Input: Sendable, Event: Sendable>: Sendable {
    public typealias Handler = @Sendable (Input) -> AsyncThrowingStream<Event, Error>

    private struct State: Sendable {
        var handler: Handler
        var calls: [Input] = []
    }

    public let name: String
    private let state: OSAllocatedUnfairLock<State>

    public init(_ name: String) {
        self.name = name
        state = OSAllocatedUnfairLock(initialState: State(handler: { _ in AsyncThrowingStream { $0.finish() } }))
    }

    public var handler: Handler {
        get { state.withLock { $0.handler } }
        set { state.withLock { $0.handler = newValue } }
    }

    public var calls: [Input] { state.withLock { $0.calls } }
    public var callCount: Int { state.withLock { $0.calls.count } }
    public var lastCall: Input? { state.withLock { $0.calls.last } }

    /// Every call yields `events` in order, then finishes (or fails with `error`).
    public func replays(_ events: [Event], thenFails error: (any Error & Sendable)? = nil) {
        handler = { _ in
            AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish(throwing: error)
            }
        }
    }

    public func callAsFunction(_ input: Input) -> AsyncThrowingStream<Event, Error> {
        let current = state.withLock { state -> Handler in
            state.calls.append(input)
            return state.handler
        }
        return current(input)
    }
}
