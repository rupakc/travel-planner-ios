import Foundation
import Networking
import VoyagerData
import VoyagerModel

/// The one door to the social routes (`/api/social/*`). It never calls a route while `features.social` is off (an older
/// backend, or a missing `/config`, just has no social screens), and a 404 that says the feature is off or the route is
/// missing turns it off for the session instead of retrying (`/config` is cached 5 minutes server-side). It is reset when
/// the signed-in user changes.
@MainActor
public final class SocialService {
    /// Thrown instead of calling a route whose flag is off.
    public struct Unavailable: Error, Equatable, Sendable {}

    private unowned let env: AppEnvironment
    private var degraded = false

    public init(env: AppEnvironment) {
        self.env = env
    }

    /// Entry points (the Ideas segment, profile rows) show only while this is true.
    public var isAvailable: Bool { !degraded && RemoteFeatures(config: env.clientConfig).social }

    /// Runs one repository call. Anything but a feature-off 404 is rethrown unchanged for the caller to translate with
    /// `SocialFailure.from`.
    public func call<T>(_ operation: (any SocialRepository) async throws -> T) async throws -> T {
        guard isAvailable else { throw Unavailable() }
        do {
            return try await operation(env.repos.social)
        } catch let error as APIError {
            if SocialFailure.isFeatureOff(error) { degraded = true }
            throw error
        }
    }

    /// A user switch or sign-out: the next user starts with the flags `/config` says.
    public func reset() {
        degraded = false
    }
}

/// The one door to the Play routes (`/api/play/*`): the same rules as `SocialService`, plus the hidden game. Play is
/// hidden whole (entry points, notifications, boards) when the account hides the game: a `403 game_hidden` turns it off
/// until the next user switch, and `hideGameSetting` (the account setting, once the app can read it) does so up front.
@MainActor
public final class PlayService {
    public struct Unavailable: Error, Equatable, Sendable {}

    private unowned let env: AppEnvironment
    private var degraded = false
    private var hiddenByServer = false

    /// The account's `hide_game`; nil while it cannot be read (then the server's `403 game_hidden` decides).
    public var hideGameSetting: @MainActor () -> Bool? = { nil }

    public init(env: AppEnvironment) {
        self.env = env
    }

    /// `features.play` already means `PLAY_ENABLED` and `GAME_ENABLED`.
    public var isAvailable: Bool {
        !degraded && !hiddenByServer && hideGameSetting() != true && RemoteFeatures(config: env.clientConfig).play
    }

    /// True once Play answered `403 game_hidden` for this user.
    public var isHiddenByServer: Bool { hiddenByServer }

    public func call<T>(_ operation: (any PlayRepository) async throws -> T) async throws -> T {
        guard isAvailable else { throw Unavailable() }
        do {
            return try await operation(env.repos.play)
        } catch let error as APIError {
            if PlayFailure.isGameHidden(error) {
                hiddenByServer = true
            } else if PlayFailure.isFeatureOff(error) {
                degraded = true
            }
            throw error
        }
    }

    public func reset() {
        degraded = false
        hiddenByServer = false
    }
}
