import DesignSystem
import Domain
import L10n
import SwiftUI

/// Ids used by the views (the quiz table itself lives in Domain).
enum TravellerQuizIDs {
    static var last: String { TravellerQuiz.questions.last?.id ?? "" }
}

/// Step 2: the six quiz questions as sub-pages, then the traveller-type result.
struct HowYouTravelStep: View {
    let model: OnboardingModel

    var body: some View {
        if let question = model.currentQuestion {
            QuizPage(model: model, question: question)
        } else {
            TravellerTypeResult(classification: model.classification)
        }
    }
}
