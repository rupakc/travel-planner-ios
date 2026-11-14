import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// "Get a timing tip" (flights): the AI advisor's one-line tip, labelled as AI-generated. Loading, the tip and an
/// error each have their own state; the button stays available after an error so a person can retry.
struct AIAdviceButton: View {
    let model: PriceStoryModel
    let tid: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            switch model.tip {
            case .idle:
                button
            case .loading:
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text(verbatim: L10n.text(K.priceStory.tip.loading))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                }
                .accessibilityElement(children: .combine)
            case .tip(let tip):
                tipBox(tip.tip)
            case .failed(let message):
                Text(verbatim: message)
                    .font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                button
            }
        }
    }

    private var button: some View {
        VButton(L10n.text(K.priceStory.tip.button), tid: tid, role: .tonal, systemImage: "sparkles") {
            Task { await model.requestTip() }
        }
    }

    private func tipBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.priceStory.tip.title))
                    .font(VFont.body(.footnote, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                Text(verbatim: L10n.text(K.priceStory.tip.ai))
                    .font(VFont.body(.caption2, weight: .medium))
                    .foregroundStyle(Palette.color(.slate, .s700))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Palette.color(.slate, .s100), in: Capsule())
            }
            // The server's text, shown as typed: no markdown, no links.
            Text(verbatim: text)
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SemanticColor.surface, in: RoundedRectangle(cornerRadius: Radius.itemCard))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("alerts.story.tip")
    }
}
