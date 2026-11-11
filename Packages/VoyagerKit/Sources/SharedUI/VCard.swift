import DesignSystem
import SwiftUI

/// A raised container with the item-card radius and a hairline border.
public struct VCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.itemCard))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border, lineWidth: 1)
            }
    }
}
