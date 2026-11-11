import Foundation
import Networking
import VoyagerModel

public struct LiveAdminRepository: AdminRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func users() async throws -> [AdminUser] { try await api.send(Endpoints.adminUsers()) }
    public func create(_ user: NewAdminUser) async throws -> AdminUser { try await api.send(Endpoints.createAdminUser(user)) }
    public func deactivate(_ username: String) async throws { _ = try await api.send(Endpoints.deactivateUser(username)) }
    public func reactivate(_ username: String) async throws { _ = try await api.send(Endpoints.reactivateUser(username)) }
    public func resetPassword(_ username: String, newPassword: String) async throws {
        _ = try await api.send(Endpoints.resetPassword(username, newPassword: newPassword))
    }
    public func feedback(page: String?, category: String?, minRating: Int?) async throws -> [FeedbackEntry] {
        try await api.send(Endpoints.adminFeedback(page: page, category: category, minRating: minRating))
    }
    public func telemetrySummary(days: Int) async throws -> TelemetrySummary {
        try await api.send(Endpoints.telemetrySummary(days: days))
    }
}
