import DesignSystem
import L10n
import SwiftUI

/// A button on a toast (Undo): shown beside the text; running it dismisses the toast.
public struct ToastAction: Sendable {
    public let title: String
    public let handler: @MainActor @Sendable () -> Void

    public init(title: String, handler: @escaping @MainActor @Sendable () -> Void) {
        self.title = title
        self.handler = handler
    }
}

public struct ToastMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let action: ToastAction?

    public init(_ text: String, action: ToastAction? = nil) {
        id = UUID()
        self.text = text
        self.action = action
    }

    public static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: ToastMessage?
    let duration: Duration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    ToastView(text: message.text, action: message.action, dismiss: { self.message = nil })
                        .padding(Spacing.lg)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .task(id: message.id) {
                            LiveRegion.announce(message.text)
                            // A toast with a button stays long enough to reach it.
                            try? await Task.sleep(for: message.action == nil ? duration : max(duration, .seconds(7)))
                            guard !Task.isCancelled else { return }
                            self.message = nil
                        }
                }
            }
            .animation(Motion.standard(reduceMotion), value: message)
    }
}

private struct ToastView: View {
    let text: String
    var action: ToastAction?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(verbatim: text)
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.onPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button {
                    action.handler()
                    dismiss()
                } label: {
                    Text(verbatim: action.title)
                        .font(VFont.body(.subheadline, weight: .semibold))
                        .foregroundStyle(SemanticColor.onPrimary)
                        .underline()
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("toast.action")
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(SemanticColor.onPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.text(K.alerts.toast.dismiss))
        }
        .padding(.leading, Spacing.lg)
        .background(Palette.color(.gray, .s900), in: RoundedRectangle(cornerRadius: Radius.itemCard))
        .frame(maxWidth: AdaptiveLayout.readableMaxWidth)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// A non-blocking message at the bottom that dismisses itself after `duration` (default 3 s), is announced to
    /// VoiceOver, and can be dismissed with its close button. Set `message` to show one.
    public func toast(_ message: Binding<ToastMessage?>, duration: Duration = .seconds(3)) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}
