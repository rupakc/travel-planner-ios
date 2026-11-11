import DesignSystem
import L10n
import SwiftUI

/// The "Estimate" tag shown next to any price that is not observed live.
public struct EstimateLabel: View {
    public init() {}

    public var body: some View {
        Text(verbatim: L10n.text(K.alerts.trip.badge.estimate))
            .font(VFont.body(.caption, weight: .medium))
            .foregroundStyle(Palette.color(.amber, .s700))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Palette.color(.amber, .s100), in: Capsule())
            .accessibilityHint(L10n.text(K.alerts.trip.badge.estimateTitle))
    }
}
