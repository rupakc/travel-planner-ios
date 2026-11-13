import Foundation
import Observation
import VoyagerEnv
import VoyagerModel

/// Failure with nothing to show but the generic copy.
struct AdminGenericFailure: ErrorPresentable {
    var presentationKind: ErrorPresentationKind { .other }
    var userFacingDetail: String? { nil }
}

func adminPresentable(_ error: any Error) -> any ErrorPresentable {
    (error as? any ErrorPresentable) ?? AdminGenericFailure()
}

/// The Users tab: list, create, deactivate (never yourself), reactivate and reset password.
@MainActor @Observable
final class UsersModel {
    nonisolated static let minPassword = 8

    private let repo: any AdminRepository
    let currentUsername: String
    private(set) var users: [AdminUser] = []
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var error: (any ErrorPresentable)?
    /// The error of the last create/reset, shown inside its sheet.
    private(set) var actionError: (any ErrorPresentable)?
    private(set) var busy: Set<String> = []
    private(set) var resetDone: String?

    init(env: AppEnvironment) {
        repo = env.repos.admin
        currentUsername = env.auth.session?.user.username ?? ""
    }

    func isSelf(_ user: AdminUser) -> Bool {
        !currentUsername.isEmpty && user.username.caseInsensitiveCompare(currentUsername) == .orderedSame
    }

    func canDeactivate(_ user: AdminUser) -> Bool { !isSelf(user) && user.isActive != false }
    func canReactivate(_ user: AdminUser) -> Bool { user.isActive == false }

    nonisolated static func validPassword(_ value: String) -> Bool { value.count >= minPassword }

    func clearActionError() { actionError = nil }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            users = try await repo.users()
            error = nil
            loaded = true
        } catch {
            if !(error is CancellationError) { self.error = adminPresentable(error) }
        }
    }

    /// `true` when the user was created.
    func create(username: String, password: String, email: String, isAdmin: Bool) async -> Bool {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, Self.validPassword(password) else { return false }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        actionError = nil
        do {
            let user = NewAdminUser(username: name, password: password, email: mail.isEmpty ? nil : mail, isAdmin: isAdmin ? true : nil)
            _ = try await repo.create(user)
            await load()
            return true
        } catch {
            actionError = adminPresentable(error)
            return false
        }
    }

    func deactivate(_ user: AdminUser) async {
        guard canDeactivate(user), !busy.contains(user.username) else { return }
        await run(user.username) { try await self.repo.deactivate(user.username) }
    }

    func reactivate(_ user: AdminUser) async {
        guard canReactivate(user), !busy.contains(user.username) else { return }
        await run(user.username) { try await self.repo.reactivate(user.username) }
    }

    private func run(_ name: String, _ action: () async throws -> Void) async {
        busy.insert(name)
        defer { busy.remove(name) }
        do {
            try await action()
            error = nil
            await load()
        } catch {
            self.error = adminPresentable(error)
        }
    }

    /// `true` when the password was reset.
    func resetPassword(username: String, newPassword: String, confirm: String) async -> Bool {
        guard Self.validPassword(newPassword), newPassword == confirm else { return false }
        actionError = nil
        do {
            try await repo.resetPassword(username, newPassword: newPassword)
            resetDone = username
            return true
        } catch {
            actionError = adminPresentable(error)
            return false
        }
    }

    func dismissResetNotice() { resetDone = nil }
}
