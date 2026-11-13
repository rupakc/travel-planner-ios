import DesignSystem
import SwiftUI

/// The rail beside a day's slots: the estimated start time, a dot and a connecting line. Named apart from
/// SwiftUI's own `TimelineView`.
struct ItineraryTimelineRail<Content: View>: View {
    let time: String?
    let isLast: Bool
    let accent: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(spacing: 0) {
                Text(verbatim: time ?? " ")
                    .font(VFont.body(.caption2, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(SemanticColor.textMuted)
                    .frame(width: 44)
                    .accessibilityHidden(true)
                Circle().fill(accent).frame(width: 10, height: 10).padding(.top, Spacing.xs)
                    .accessibilityHidden(true)
                Rectangle().fill(isLast ? Color.clear : SemanticColor.border).frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
