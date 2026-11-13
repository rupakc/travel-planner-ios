import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv

/// The stored conversations, most recent first. On iPad it is the content column beside the chat; on iPhone a sheet.
struct ThreadsList: View {
    let threads: [ChatThread]
    let selected: UUID
    let onNew: () -> Void
    let onOpen: (UUID) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(verbatim: L10n.text(K.chat.page.title))
                    .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                Spacer()
                Button(action: onNew) {
                    Label { Text(verbatim: L10n.text(K.mobile.shortcuts.newChat)) } icon: { Image(systemName: "square.and.pencil") }
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("chat.threads.new")
            }
            .padding(.horizontal, Spacing.lg)
            Divider().overlay(SemanticColor.border)
            if threads.isEmpty {
                // Compact: a long intro sentence in a 300 pt sidebar must not read as a headline.
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 22)).foregroundStyle(SemanticColor.textMuted).accessibilityHidden(true)
                    Text(verbatim: L10n.text(K.chat.page.intro))
                        .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted).multilineTextAlignment(.center)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(threads) { thread in
                        Button { onOpen(thread.id) } label: { row(thread) }
                            .listRowBackground(thread.id == selected ? SemanticColor.border.opacity(0.5) : Color.clear)
                            .swipeActions {
                                Button(role: .destructive) { onDelete(thread.id) } label: {
                                    Label { Text(verbatim: L10n.text(K.chat.action.remove)) } icon: { Image(systemName: "trash") }
                                }
                            }
                            .accessibilityIdentifier("chat.thread")
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SemanticColor.surface)
    }

    private func row(_ thread: ChatThread) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: thread.title ?? L10n.text(K.chat.page.title))
                .font(VFont.body(.subheadline, weight: .medium)).foregroundStyle(SemanticColor.text).lineLimit(2)
        }
        .frame(minHeight: 44, alignment: .leading)
    }
}
