import AuthCore
import Foundation
import L10n
import Networking
import Observation
import SharedUI
import VoyagerEnv

@MainActor @Observable
public final class ChangePasswordModel {
    /// The server's rule today.
    public static let minimumLength = 8

    public var current = ""
    public var new = ""
    public var confirm = ""
    public private(set) var isBusy = false
    public private(set) var error: String?
    public private(set) var didSucceed = false

    @ObservationIgnored private let env: AppEnvironment

    public init(env: AppEnvironment) { self.env = env }

    public var canSubmit: Bool { !isBusy && !current.isEmpty && !new.isEmpty && !confirm.isEmpty }

    /// The first rule the form breaks, or nil.
    var validationError: String? {
        if new.count < Self.minimumLength { return L10n.text(K.account.changePassword.tooShort) }
        if new != confirm { return L10n.text(K.account.changePassword.mismatch) }
        return nil
    }

    /// On success the session's token is replaced (and `requiresPasswordChange` cleared) by `AuthState`.
    public func submit() async {
        guard canSubmit else { return }
        if let problem = validationError {
            error = problem
            return
        }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await env.auth.changePassword(current: current, new: new)
            didSucceed = true
            current = ""
            new = ""
            confirm = ""
        } catch is CancellationError {
            return
        } catch {
            self.error = Self.message(for: error)
        }
    }

    static func message(for error: any Error) -> String {
        guard let api = error as? APIError else { return L10n.text(K.account.changePassword.failed) }
        switch api.presentationKind {
        case .unauthorized: return L10n.text(K.account.changePassword.failed)
        default: return ErrorCopy.message(kind: api.presentationKind, detail: api.userFacingDetail)
        }
    }
}
