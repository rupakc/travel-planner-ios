import Foundation
import Networking
import VoyagerModel

public struct LiveNotificationsRepository: NotificationsRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func page(unreadOnly: Bool, limit: Int, offset: Int) async throws -> NotificationsPage {
        try await api.send(Endpoints.notifications(unreadOnly: unreadOnly, limit: limit, offset: offset))
    }
    public func unreadCount() async throws -> Int { try await api.send(Endpoints.unreadCount()).count }
    public func markRead(ids: [Int]?, all: Bool) async throws -> Int {
        try await api.send(Endpoints.markRead(ids: ids, all: all)).unread
    }
}
