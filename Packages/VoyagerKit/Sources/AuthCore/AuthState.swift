import Foundation
import Observation

public enum SignOutReason: Sendable, Equatable { case userInitiated, sessionExpired }

public enum AuthPhase: Sendable, Equatable {
    case signedOut(reason: SignOutReason?)
    case needsPasswordChange
    case signedIn
}

/// Thread-safe copy of the current access token for `nonisolated` readers.
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return token }
        set { lock.lock(); token = newValue; lock.unlock() }
    }
}

@MainActor @Observable
public final class AuthState {
    public private(set) var session: Session?
    public private(set) var phase: AuthPhase

    @ObservationIgnored private let api: AuthAPI
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let refresher: TokenRefresher
    @ObservationIgnored private let social: SocialSignIn
    @ObservationIgnored private let box = TokenBox()

    public init(
        api: AuthAPI, store: SessionStore,
        refresher: TokenRefresher = NoTokenRefresher(),
        social: SocialSignIn = ComingSoonSocialSignIn()
    ) {
        self.api = api
        self.store = store
        self.refresher = refresher
        self.social = social
        let stored = store.load()
        session = stored
        phase = Self.phase(for: stored, reason: nil)
        box.value = stored?.accessToken
    }

    private static func phase(for next: Session?, reason: SignOutReason?) -> AuthPhase {
        guard let next else { return .signedOut(reason: reason) }
        return next.user.requiresPasswordChange ? .needsPasswordChange : .signedIn
    }

    private func adopt(_ next: Session) throws {
        try store.save(next)
        session = next
        phase = Self.phase(for: next, reason: nil)
        box.value = next.accessToken
    }

    private func drop(reason: SignOutReason) {
        store.clear()
        session = nil
        phase = .signedOut(reason: reason)
        box.value = nil
    }

    public func signIn(username: String, password: String) async throws {
        let resp = try await api.login(username: username, password: password)
        try adopt(Session(accessToken: resp.accessToken, user: resp.user, method: .password))
    }

    public func signIn(with provider: AuthProviderID, info: AuthProviderInfo) async throws {
        guard info.configured else { throw AuthError.comingSoon(provider) }
        try adopt(try await social.signIn(provider, info: info))
    }

    public func changePassword(current: String, new: String) async throws {
        guard var next = session else { throw AuthError.sessionExpired }
        let token = try await api.changePassword(current: current, new: new)
        next.accessToken = token
        next.accessExpiresAt = JWTClaims.expiry(of: token)
        next.user.requiresPasswordChange = false
        try adopt(next)
    }

    public func signOut() async { drop(reason: .userInitiated) }

    /// A 401 arrived for `token`. Only the current token matters: a late 401 for a previous token is ignored.
    /// A refresher is tried first; if it cannot help the user is signed out with `.sessionExpired`.
    public func handleUnauthorized(token: String?) async {
        guard let current = session, token == current.accessToken else { return }
        if current.refreshToken != nil, let fresh = try? await refresher.refresh(current) {
            guard session?.accessToken == current.accessToken else { return }
            if (try? adopt(fresh)) != nil { return }
        }
        guard session?.accessToken == current.accessToken else { return }
        drop(reason: .sessionExpired)
    }

    public nonisolated func tokenSnapshot() -> String? { box.value }
}
