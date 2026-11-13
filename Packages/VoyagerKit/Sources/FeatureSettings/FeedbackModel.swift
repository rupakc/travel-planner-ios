import Foundation
import Observation
import VoyagerEnv
import VoyagerModel

/// The feedback form: rating 1-5, category, message of at most 500 characters.
@MainActor @Observable
final class FeedbackModel {
    nonisolated static let maxMessage = 500
    nonisolated static let categories = ["bug", "feature_request", "general", "praise"]

    private let env: AppEnvironment
    var rating = 0
    var category = "general"
    private(set) var message = ""
    private(set) var sending = false
    private(set) var sent = false
    private(set) var error: (any ErrorPresentable)?

    init(env: AppEnvironment) { self.env = env }

    func updateMessage(_ text: String) { message = String(text.prefix(Self.maxMessage)) }

    var canSend: Bool { (1...5).contains(rating) && !sending }

    func send() async {
        guard canSend else { return }
        sending = true
        error = nil
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let submission = FeedbackSubmission(
            page: "other", rating: rating, category: category, message: text.isEmpty ? nil : String(text.prefix(Self.maxMessage)))
        do {
            try await env.repos.feedback.submit(submission)
            sent = true
        } catch {
            self.error = error as? any ErrorPresentable
            if self.error == nil { self.error = GenericFailure() }
        }
        sending = false
    }
}

private struct GenericFailure: ErrorPresentable {
    var presentationKind: ErrorPresentationKind { .other }
    var userFacingDetail: String? { nil }
}
