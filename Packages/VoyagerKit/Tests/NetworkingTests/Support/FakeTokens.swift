import Foundation
import os
import Networking

final class FakeTokens: AccessTokenProvider, Sendable {
    private struct State {
        var token: String?
        var refreshesTo: String?
        var unauthorizedTokens: [String] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    /// `refreshesTo`: the token `unauthorized` installs (returning true); nil makes it return false.
    init(token: String?, refreshesTo: String? = nil) {
        state = OSAllocatedUnfairLock(initialState: State(token: token, refreshesTo: refreshesTo))
    }

    var unauthorizedTokens: [String] { state.withLock { $0.unauthorizedTokens } }

    func currentToken() async -> String? { state.withLock { $0.token } }

    func unauthorized(token: String) async -> Bool {
        state.withLock {
            $0.unauthorizedTokens.append(token)
            guard let fresh = $0.refreshesTo else { return false }
            $0.token = fresh
            return true
        }
    }
}

final class RecordingObserver: APIObserver, Sendable {
    private let failures = OSAllocatedUnfairLock(initialState: [String]())
    var recorded: [String] { failures.withLock { $0 } }
    func didFail(endpoint: String, status: Int) { failures.withLock { $0.append("\(status) \(endpoint)") } }
}
