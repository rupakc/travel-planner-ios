import DesignSystem
import SwiftUI
import VoyagerModel

/// The advice for a story, in words, from `advice.code` and its params. Nothing to show for an unknown code.
struct AdviceLine: View {
    let advice: StoryAdvice?
    let currency: String?

    private var symbol: String {
        switch advice?.code {
        case .belowTarget, .atLowest, .belowTypical: "arrow.down.circle"
        case .nearTarget: "scope"
        case .checksPaused: "pause.circle"
        case .aboveTypical: "arrow.up.circle"
        case .pending: "hourglass"
        default: "info.circle"
        }
    }

    var body: some View {
        if let text = PriceStoryModel.adviceText(advice, currency: currency) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: symbol)
                    .foregroundStyle(SemanticColor.primary)
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("alerts.story.advice")
        }
    }
}
