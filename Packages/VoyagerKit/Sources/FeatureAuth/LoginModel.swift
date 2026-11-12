import AuthCore
import Foundation
import L10n
import Networking
import Observation
import SharedUI
import VoyagerEnv

/// State of the login form. A successful sign-in changes `env.auth.phase`, which the app's gate follows.
@MainActor @Observable
public final class LoginModel {
    public var username = ""
    public var password = ""
    public var showPassword = false
    public private(set) var isBusy = false
    public private(set) var error: String?

    @ObservationIgnored private let env: AppEnvironment

    public init(env: AppEnvironment) { self.env = env }

    public var canSubmit: Bool {
        !isBusy && !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    public func submit() async {
        guard canSubmit else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await env.auth.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
        } catch is CancellationError {
            return
        } catch {
            self.error = Self.message(for: error)
        }
    }

    /// 401 is "wrong username or password" here (never the session-expired copy); a rate limit shows the
    /// backend's own text; anything else gets the generic copy.
    static func message(for error: any Error) -> String {
        if let auth = error as? AuthError, auth == .invalidCredentials { return L10n.text(K.account.login.failed) }
        if let api = error as? APIError {
            switch api.presentationKind {
            case .unauthorized: return L10n.text(K.account.login.failed)
            default: return ErrorCopy.message(kind: api.presentationKind, detail: api.userFacingDetail)
            }
        }
        return L10n.text(K.account.login.failed)
    }
}
