import DesignSystem
import L10n
import SwiftUI

/// The calm note while live checks are off (`features.live_prices` false): watches keep their last prices, each shows
/// when it was checked. Never says anything about a "great price now".
struct PausedBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "pause.circle")
                .font(.title3)
                .foregroundStyle(SemanticColor.textMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.alertsHub.paused.title))
                    .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                Text(verbatim: L10n.text(K.alertsHub.paused.body))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.lg)
        .borderedSurface(RoundedRectangle(cornerRadius: Radius.itemCard), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("alerts.live-paused")
    }
}
