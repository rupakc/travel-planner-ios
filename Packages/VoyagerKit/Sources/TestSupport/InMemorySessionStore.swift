import AuthCore
import Foundation
import os

/// A `SessionStore` in memory (no Keychain), recording saves and clears.
public final class InMemorySessionStore: SessionStore {
    private struct State: Sendable {
        var session: Session?
        var saves = 0
        var clears = 0
        var loads = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(_ session: Session? = nil) {
        state = OSAllocatedUnfairLock(initialState: State(session: session))
    }

    public var session: Session? { state.withLock { $0.session } }
    public var saveCount: Int { state.withLock { $0.saves } }
    public var clearCount: Int { state.withLock { $0.clears } }
    public var loadCount: Int { state.withLock { $0.loads } }

    public func load() -> Session? {
        state.withLock { state in
            state.loads += 1
            return state.session
        }
    }

    public func save(_ session: Session) throws {
        state.withLock { state in
            state.session = session
            state.saves += 1
        }
    }

    public func clear() {
        state.withLock { state in
            state.session = nil
            state.clears += 1
        }
    }
}
