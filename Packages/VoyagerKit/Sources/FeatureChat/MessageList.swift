import DesignSystem
import L10n
import SectionsUI
import SharedUI
import SwiftUI

/// The conversation, newest at the bottom; follows the stream while the reader is at the end.
/// `lazy: false` is for snapshot hosting, where lazy stacks hang.
struct MessageList: View {
    let messages: [ChatMessageState]
    let isStreaming: Bool
    let ctx: SectionContext
    let lazy: Bool
    let onSuggestion: (String) -> Void
    let onImport: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if lazy {
                    LazyVStack(alignment: .leading, spacing: Spacing.lg) { rows }.padding(Spacing.lg)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.lg) { rows }.padding(Spacing.lg)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.last?.content) { scrollToEnd(proxy) }
            .onChange(of: messages.count) { scrollToEnd(proxy) }
        }
    }

    @ViewBuilder private var rows: some View {
        ForEach(messages) { message in
            MessageBubble(
                message: message, isLast: message.id == messages.last?.id, isStreaming: isStreaming, ctx: ctx,
                onSuggestion: onSuggestion, onImport: onImport, onRetry: onRetry)
                .id(message.id)
        }
        Text(verbatim: L10n.text(K.chat.page.disclaimer))
            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .id("chat.end")
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }
}
