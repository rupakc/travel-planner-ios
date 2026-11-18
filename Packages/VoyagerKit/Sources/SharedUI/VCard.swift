import DesignSystem
import SwiftUI

private struct VCardFillsHeightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a grid row: its cards take the height of the tallest card beside them and align to the top.
    public var vCardFillsHeight: Bool {
        get { self[VCardFillsHeightKey.self] }
        set { self[VCardFillsHeightKey.self] = newValue }
    }
}

/// A raised container with the item-card radius and a hairline border.
public struct VCard<Content: View>: View {
    private let content: Content
    @Environment(\.vCardFillsHeight) private var fillsHeight

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? CGFloat.infinity : nil, alignment: fillsHeight ? .topLeading : .leading)
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.itemCard))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border, lineWidth: 1)
            }
    }
}
