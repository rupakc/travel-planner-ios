import DesignSystem
import SwiftUI

extension View {
    /// Themed text field: raised surface with a 1 pt border (the system rounded-border style renders black in dark).
    func prefsField() -> some View {
        textFieldStyle(.plain)
            .font(VFont.body(.body))
            .foregroundStyle(SemanticColor.text)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 44)
            .borderedSurface(
                RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
    }
}
