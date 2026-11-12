import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI

/// One quiz question: its options as chips (single or multiple choice).
struct QuizPage: View {
    let model: OnboardingModel
    let question: QuizQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(verbatim: QuizLabels.title(question.id))
                .font(VFont.display(.title2))
                .foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // A plain stack (not lazy): the lists are short and snapshot hosting hangs on lazy stacks.
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(question.options, id: \.id) { option in
                    VChip(
                        title: QuizLabels.option(question.id, option.id),
                        tid: "onboarding.\(question.id).\(option.id)",
                        selected: model.isSelected(option, in: question)
                    ) { model.toggle(option, in: question) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The catalogue keys of the quiz and traveller types are built from ids (`onboarding:quiz.<q>.options.<o>`).
enum QuizLabels {
    static func title(_ question: String) -> String {
        L10n.text(LKey("onboarding:quiz.\(question).title", placeholders: [], plural: false))
    }

    static func option(_ question: String, _ option: String) -> String {
        L10n.text(LKey("onboarding:quiz.\(question).options.\(option)", placeholders: [], plural: false))
    }

    static func typeName(_ type: TravellerType) -> String {
        L10n.text(LKey("onboarding:types.\(type.rawValue).name", placeholders: [], plural: false))
    }

    static func typeDescription(_ type: TravellerType) -> String {
        L10n.text(LKey("onboarding:types.\(type.rawValue).description", placeholders: [], plural: false))
    }
}
