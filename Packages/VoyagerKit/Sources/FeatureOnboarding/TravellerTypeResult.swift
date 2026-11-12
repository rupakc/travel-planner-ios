import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI

/// The result of the quiz: the primary type, with the secondary ones named underneath.
struct TravellerTypeResult: View {
    let classification: (primary: TravellerType, secondary: [TravellerType])

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(verbatim: L10n.text(K.onboarding.ui.yourType))
                .font(VFont.body(.footnote, weight: .medium))
                .foregroundStyle(SemanticColor.textMuted)
                .accessibilityAddTraits(.isHeader)
            VCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: QuizLabels.typeName(classification.primary))
                        .font(VFont.display(.title2))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: QuizLabels.typeDescription(classification.primary))
                        .font(VFont.body(.body))
                        .foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !classification.secondary.isEmpty {
                Text(verbatim: L10n.text(
                    K.onboarding.ui.alsoLike,
                    ["types": classification.secondary.map(QuizLabels.typeName).joined(separator: ", ")]))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
