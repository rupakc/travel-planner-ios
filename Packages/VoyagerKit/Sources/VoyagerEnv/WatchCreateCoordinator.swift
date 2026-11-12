import Foundation
import Networking
import VoyagerModel

/// What a "Watch price" tap produced.
public enum WatchCreateResult: Sendable, Equatable {
    case created(WatchKind, Int)
    case alreadyWatching(WatchKind, Int)
    /// `422 no_live_price`, with the copy to show.
    case noLivePrice(String)
    case failed(APIError)
}

/// Serves watch requests from Results and Chat. Stub: Task 32 replaces this file (same signature) with
/// match-then-create over `env.repos.watches`.
@MainActor
public final class WatchCreateCoordinator {
    private unowned let env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
    }

    public func handle(_ request: WatchRequest) async -> WatchCreateResult {
        _ = (env, request)
        return .failed(.notConfigured)
    }
}
