import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// Followers, following, follow requests or blocked people: handles only, with the action each list needs.
struct ProfileListView: View {
    @State private var model: ProfileListModel

    @MainActor init(model: ProfileListModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) { content }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
        }
        .background(SemanticColor.surface)
        .navigationTitle(model.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .refreshable { await model.load() }
        .accessibilityIdentifier("profile.list")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.social.feed.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
        case .unavailable:
            Text(verbatim: L10n.text(K.social.errors.not_found))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
        case .failed(let kind, let detail):
            ProfileFailureView(message: ErrorCopy.message(kind: kind, detail: detail), tid: "profile.list.retry") {
                Task { await model.load() }
            }
        case .loaded:
            if let text = model.errorText {
                Text(verbatim: text).font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.people.isEmpty {
                EmptyState(icon: "person.2", title: model.emptyText).accessibilityIdentifier("profile.list.empty")
            }
            ForEach(model.people) { person in row(person) }
            if model.canLoadMore {
                VButton(L10n.text(K.social.feed.loadMore), tid: "profile.list.more", role: .secondary) {
                    Task { await model.loadMore() }
                }
            }
        }
    }

    private func row(_ person: ProfilePerson) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button { model.open(person) } label: {
                    Text(verbatim: "@" + person.handle)
                        .font(VFont.body(.body, weight: .semibold)).foregroundStyle(SemanticColor.text)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .multilineTextAlignment(.leading).frame(minHeight: 44, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                switch model.kind {
                case .requests:
                    ActionPair {
                        VButton(L10n.text(K.social.editor.decline), tid: "profile.decline", role: .secondary) {
                            Task { await model.decline(person) }
                        }
                    } second: {
                        VButton(L10n.text(K.social.editor.accept), tid: "profile.accept") { Task { await model.accept(person) } }
                    }
                    .disabled(model.busy.contains(person.handle))
                case .blocked:
                    VButton(L10n.text(K.social.block.unblock), tid: "profile.unblock", role: .secondary) {
                        Task { await model.unblock(person) }
                    }
                    .disabled(model.busy.contains(person.handle))
                case .followers, .following:
                    EmptyView()
                }
            }
        }
    }
}
