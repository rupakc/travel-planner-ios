import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry

/// The message field with send (stop while a reply streams).
struct Composer: View {
    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    @Environment(\.telemetryRoute) private var route
    @FocusState private var focused: Bool

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            TextField(text: $text, axis: .vertical) {
                Text(verbatim: L10n.text(K.chat.page.placeholder))
            }
            .lineLimit(1...5)
            .font(VFont.body(.body))
            .focused($focused)
            .submitLabel(.send)
            .onSubmit { send() }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: 44)
            .background(SemanticColor.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Radius.largeCard))
            .overlay { RoundedRectangle(cornerRadius: Radius.largeCard).strokeBorder(SemanticColor.border, lineWidth: 1) }
            .accessibilityIdentifier("chat.input")
            actionButton
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(SemanticColor.surface)
    }

    @ViewBuilder private var actionButton: some View {
        if isStreaming {
            Button {
                Telemetry.shared.track(.uiTap(tid: "chat.stop", route: route))
                onStop()
            } label: {
                Image(systemName: "stop.fill").frame(width: 44, height: 44)
                    .foregroundStyle(SemanticColor.onPrimary)
                    .background(SemanticColor.primary, in: Circle())
            }
            .accessibilityLabel(Text(verbatim: L10n.text(K.chat.page.stop)))
            .accessibilityIdentifier("chat.stop")
        } else {
            Button(action: send) {
                Image(systemName: "arrow.up").frame(width: 44, height: 44)
                    .foregroundStyle(SemanticColor.onPrimary)
                    .background(canSend ? SemanticColor.primary : SemanticColor.textMuted, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel(Text(verbatim: L10n.text(K.chat.page.send)))
            .accessibilityIdentifier("chat.send")
        }
    }

    private func send() {
        guard canSend else { return }
        Telemetry.shared.track(.uiSubmit(tid: "chat.send", route: route))
        onSend()
    }
}
