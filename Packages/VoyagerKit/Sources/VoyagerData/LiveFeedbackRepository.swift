import Foundation
import Networking
import VoyagerModel

public struct LiveFeedbackRepository: FeedbackRepository {
    private let api: APIClient
    public init(api: APIClient, locale: @escaping @Sendable () -> AppLanguage) { self.api = api }

    public func submit(_ feedback: FeedbackSubmission) async throws { _ = try await api.send(Endpoints.feedback(feedback)) }
}
