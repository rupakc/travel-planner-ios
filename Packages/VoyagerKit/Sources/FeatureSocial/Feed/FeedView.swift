import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// The Ideas feed (a segment of the Discover tab): scope chips, idea cards (two columns on iPad), "show more", and the
/// support contact.
public struct IdeasFeedView: View {
    @State private var model: FeedModel
    @State private var reporting: ReportItem?
    @State private var blocking: Idea?
    @State private var deleting: Idea?
    @Environment(\.horizontalSizeClass) private var sizeClass
    private let env: AppEnvironment
    private let supportURL: URL?

    @MainActor public init(env: AppEnvironment) {
        self.env = env
        self.supportURL = env.build.supportURL
        _model = State(initialValue: FeedModel(env: env))
    }

    @MainActor init(model: FeedModel, env: AppEnvironment, supportURL: URL? = nil) {
        self.env = env
        self.supportURL = supportURL
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if model.showsProfilePrompt { profilePrompt }
                scopeChips
                content
                SupportRow(url: supportURL)
            }
            .frame(maxWidth: sizeClass == .regular ? 1000 : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
        }
        .background(SemanticColor.surface)
        .task { await model.start() }
        .refreshable { await model.load() }
        .sheet(item: $reporting) { item in
            ReportSheetView(model: item.model, supportURL: supportURL)
        }
        .confirmationDialog(
            L10n.text(K.social.idea.deleteConfirm), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.text(K.social.idea.delete), role: .destructive) {
                if let idea = deleting { Task { await model.delete(idea.id) } }
            }
            Button(L10n.text(K.social.actions.cancel), role: .cancel) {}
        }
        .confirmationDialog(
            blocking.map { L10n.text(K.social.block.confirm, ["handle": $0.author.handle]) } ?? "",
            isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible
        ) {
            Button(L10n.text(K.social.block.yes), role: .destructive) {
                if let idea = blocking { Task { await block(idea) } }
            }
            Button(L10n.text(K.social.actions.cancel), role: .cancel) {}
        }
        .accessibilityIdentifier("feed.root")
    }

    private func block(_ idea: Idea) async {
        do {
            try await env.social.call { try await $0.block(handle: idea.author.handle) }
            model.blocked(handle: idea.author.handle)
        } catch {
            // The next load tells the truth; a failed block leaves the card.
        }
    }

    // MARK: Parts

    private var profilePrompt: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.social.feed.profilePrompt))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                VButton(L10n.text(K.social.feed.createProfile), tid: "feed.create-profile", role: .secondary) {
                    env.router.open(.profileEditor)
                }
            }
        }
        .accessibilityIdentifier("feed.profile-prompt")
    }

    private var scopeChips: some View {
        SocialActionWrap(spacing: Spacing.sm) {
            ForEach(FeedScope.allCases, id: \.self) { scope in
                VChip(title: Self.title(scope), tid: "feed.scope.\(scope.rawValue)", selected: model.scope == scope) {
                    Task { await model.select(scope) }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(Text(verbatim: L10n.text(K.social.feed.scopes)))
        .accessibilityIdentifier("feed.scopes")
    }

    static func title(_ scope: FeedScope) -> String {
        switch scope {
        case .forYou: L10n.text(K.social.feed.scope.for_you)
        case .following: L10n.text(K.social.feed.scope.following)
        case .new: L10n.text(K.social.feed.scope.new)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.social.feed.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
                .accessibilityIdentifier("feed.loading")
        case .unavailable:
            EmptyState(icon: "lightbulb", title: L10n.text(K.social.errors.not_found))
                .accessibilityIdentifier("feed.unavailable")
        case .failed(let failure):
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: failure.message)
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                VButton(L10n.text(K.social.feed.retry), tid: "feed.retry", role: .secondary) { Task { await model.load() } }
            }
            .accessibilityIdentifier("feed.failed")
        case .loaded:
            loaded
        }
    }

    @ViewBuilder private var loaded: some View {
        if model.isEmpty {
            EmptyState(
                icon: "lightbulb",
                title: L10n.text(model.scope == .following ? K.social.feed.emptyFollowing : K.social.feed.empty))
                .accessibilityIdentifier("feed.empty")
        } else {
            cards
        }
        if model.hasMore {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let failure = model.loadMoreFailure {
                    Text(verbatim: failure.message)
                        .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let moreTitle = L10n.text(model.isLoadingMore ? K.social.feed.loading : K.social.feed.loadMore)
                VButton(moreTitle, tid: "feed.more", role: .secondary) {
                    Task { await model.loadMore() }
                }
                .disabled(model.isLoadingMore)
            }
        }
    }

    @ViewBuilder private var cards: some View {
        let ideas = model.visible
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: Spacing.lg) {
                VStack(spacing: Spacing.lg) { ForEach(column(ideas, 0)) { card($0) } }
                VStack(spacing: Spacing.lg) { ForEach(column(ideas, 1)) { card($0) } }
            }
            .accessibilityIdentifier("feed.columns")
        } else {
            VStack(spacing: Spacing.lg) { ForEach(ideas) { card($0) } }
        }
    }

    private func card(_ idea: Idea) -> some View {
        IdeaCardView(
            idea: idea,
            state: IdeaCardState(failure: model.actionFailure[idea.id], savedNote: model.savedNote.contains(idea.id)),
            actions: IdeaCardActions(
                open: { model.opened(idea) },
                like: { Task { await model.toggleLike(idea.id) } },
                save: { Task { await model.save(idea.id) } },
                comments: { model.opened(idea) },
                report: { reporting = ReportItem(model: ReportModel(target: .idea, id: idea.id, env: env)) },
                block: { blocking = idea },
                delete: { deleting = idea }))
    }

    private func column(_ ideas: [Idea], _ parity: Int) -> [Idea] {
        ideas.enumerated().filter { $0.offset % 2 == parity }.map(\.element)
    }
}

/// A report sheet to present (`sheet(item:)` needs an `Identifiable`).
struct ReportItem: Identifiable {
    let id = UUID()
    let model: ReportModel
}
