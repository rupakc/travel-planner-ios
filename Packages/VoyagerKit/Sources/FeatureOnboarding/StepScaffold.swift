import DesignSystem
import SwiftUI

/// The shared look of a step: icon, heading and body, then the step's own content.
struct StepScaffold<Content: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(SemanticColor.primary)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(VFont.display(.title2))
                .foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: message)
                .font(VFont.body(.body))
                .foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
