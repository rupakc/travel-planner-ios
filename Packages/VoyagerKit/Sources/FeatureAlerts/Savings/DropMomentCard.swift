import DesignSystem
import L10n
import SwiftUI

/// "Caught a drop of $46.00 (9%)": the two observed prices, the target-hit variant, and (only when the game is
/// visible) the XP and badges the server awarded for this drop. Sits inside the inbox row of a drop notification.
struct DropMomentCard: View {
    let content: DropMomentContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: content.targetHit ? "target" : "arrow.down.right.circle.fill")
                    .foregroundStyle(SemanticColor.primary)
                    .accessibilityHidden(true)
                Text(verbatim: content.heading)
                    .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            amount
            if let from = content.fromText, let to = content.toText {
                priceLine(from: from, to: to)
            }
            if content.xpText != nil || !content.badgeTexts.isEmpty { game }
            Text(verbatim: content.note)
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .borderedSurface(
            RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surface, border: SemanticColor.border)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox.drop")
    }

    private var amount: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(verbatim: content.amountText)
                .font(VFont.display(.title2)).foregroundStyle(SemanticColor.primary)
                .minimumScaleFactor(0.6).lineLimit(1)
            if !content.percentText.isEmpty {
                Text(verbatim: L10n.text(K.dropMoment.percentInline, ["percent": content.percentText]))
                    .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.spoken)
    }

    private func priceLine(from: String, to: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(verbatim: from).strikethrough().foregroundStyle(SemanticColor.textMuted)
            Image(systemName: "arrow.right").foregroundStyle(SemanticColor.textMuted).accessibilityHidden(true)
            Text(verbatim: to).fontWeight(.semibold).foregroundStyle(SemanticColor.text)
        }
        .font(VFont.body(.subheadline))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(from), \(L10n.text(K.dropMoment.nowPrice)) \(to)")
    }

    private var game: some View {
        AlertsWrapLayout(spacing: Spacing.sm) {
            if let xp = content.xpText { pill(xp, id: "inbox.drop.xp") }
            ForEach(content.badgeTexts, id: \.self) { pill($0, id: "inbox.drop.badge") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ text: String, id: String) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.text)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
            .borderedSurface(Capsule(), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
            .accessibilityIdentifier(id)
    }
}
