import DesignSystem
import SwiftUI

public struct EmptyStateAction {
    public let title: String
    public let tid: String
    public let handler: () -> Void

    public init(title: String, tid: String, handler: @escaping () -> Void) {
        self.title = title
        self.tid = tid
        self.handler = handler
    }
}

/// Icon, title, optional message and optional action, centred. All text is already localized.
public struct EmptyState: View {
    private let icon: String
    private let title: String
    private let message: String?
    private let action: EmptyStateAction?

    public init(icon: String, title: String, message: String? = nil, action: EmptyStateAction? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(SemanticColor.textMuted)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(VFont.display(.title3))
                .foregroundStyle(SemanticColor.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(verbatim: message)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
                    .multilineTextAlignment(.center)
            }
            if let action {
                VButton(action.title, tid: action.tid, role: .secondary, action: action.handler)
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
