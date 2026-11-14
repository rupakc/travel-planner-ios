import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// The notification inbox: price alerts newest first, "Mark all as read", and a tap that opens the watch.
public struct NotificationsInboxView: View {
    @State private var model: NotificationsModel

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: NotificationsModel(env: env))
    }

    @MainActor init(model: NotificationsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.md) {
                content
            }
            .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
        }
        .refreshable { await model.load() }
        .navigationTitle(L10n.text(K.alerts.bell.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if model.phase == .loaded, model.unread > 0 {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.text(K.alerts.bell.markAll)) { Task { await model.markAllRead() } }
                        .accessibilityIdentifier("inbox.mark-all")
                }
            }
        }
        .task { await model.load() }
        .toast($model.toast)
        .accessibilityIdentifier("inbox.root")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: Spacing.md) {
                ProgressView()
                Text(verbatim: L10n.text(K.alerts.bell.loading))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            }
        case .failed(let message):
            VStack(spacing: Spacing.md) {
                Text(verbatim: message).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                VButton(L10n.text(K.alerts.ui.retry), tid: "inbox.retry", role: .secondary) { Task { await model.load() } }
            }
        case .unavailable:
            EmptyState(icon: "tray", title: L10n.text(K.alerts.bell.emptyTitle), message: L10n.text(K.alerts.bell.emptyBody))
        case .loaded:
            if model.items.isEmpty {
                EmptyState(icon: "tray", title: L10n.text(K.alerts.bell.emptyTitle), message: L10n.text(K.alerts.bell.emptyBody))
            } else {
                ForEach(model.items, id: \.id) { item in row(item) }
                if model.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await model.loadMore() }
                }
            }
        }
    }

    private func row(_ item: AppNotification) -> some View {
        let unread = item.readAt == nil
        return Button {
            Task { await model.open(item) }
        } label: {
            HStack(alignment: .top, spacing: Spacing.md) {
                Circle()
                    .fill(unread ? SemanticColor.primary : Color.clear)
                    .frame(width: 10, height: 10)
                    .padding(.top, Spacing.xs)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: item.title ?? "")
                        .font(VFont.body(.subheadline, weight: unread ? .semibold : .regular))
                        .foregroundStyle(SemanticColor.text)
                        .multilineTextAlignment(.leading)
                    if let body = item.body, !body.isEmpty {
                        Text(verbatim: body).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                    if let age = model.ageText(item) {
                        Text(verbatim: age).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                    }
                    InboxRowSlot(item: item)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.md)
            .frame(minHeight: 44)
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.itemCard))
            .overlay { RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? L10n.text(K.alerts.bell.unreadBadge) : "")
        .accessibilityIdentifier("inbox.row.\(item.id)")
    }
}
