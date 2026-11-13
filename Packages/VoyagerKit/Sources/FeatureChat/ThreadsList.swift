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
                EmptyState(icon: "bubble.left.and.bubble.right", title: L10n.text(K.chat.page.intro))
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
