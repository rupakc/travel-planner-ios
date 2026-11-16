import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// One idea with its comments (`Route.ideaDetail`).
public struct IdeaDetailView: View {
    @State private var model: IdeaDetailModel
    @State private var comments: CommentsModel
    @State private var reporting: ReportItem?
    @State private var confirmDelete = false
    @State private var confirmBlock = false
    private let env: AppEnvironment
    private let supportURL: URL?

    @MainActor public init(env: AppEnvironment, ideaID: String) {
        let detail = IdeaDetailModel(env: env, ideaID: ideaID)
        self.env = env
        self.supportURL = env.build.supportURL
        _model = State(initialValue: detail)
        _comments = State(initialValue: CommentsModel(env: env, ideaID: ideaID, ideaMine: false))
    }

    @MainActor init(model: IdeaDetailModel, comments: CommentsModel, env: AppEnvironment, supportURL: URL? = nil) {
        self.env = env
        self.supportURL = supportURL
        _model = State(initialValue: model)
        _comments = State(initialValue: comments)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                content
                SupportRow(url: supportURL)
            }
            .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
        }
        .background(SemanticColor.surface)
        .navigationTitle(L10n.text(K.social.feed.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.start() }
        .sheet(item: $reporting) { ReportSheetView(model: $0.model, supportURL: supportURL) }
        .confirmationDialog(L10n.text(K.social.idea.deleteConfirm), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.text(K.social.idea.delete), role: .destructive) { Task { await model.delete() } }
            Button(L10n.text(K.social.actions.cancel), role: .cancel) {}
        }
        .confirmationDialog(
            model.idea.map { L10n.text(K.social.block.confirm, ["handle": $0.author.handle]) } ?? "", isPresented: $confirmBlock,
            titleVisibility: .visible
        ) {
            Button(L10n.text(K.social.block.yes), role: .destructive) { Task { _ = await model.block() } }
            Button(L10n.text(K.social.actions.cancel), role: .cancel) {}
        }
        .accessibilityIdentifier("idea.root")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.social.feed.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
                .accessibilityIdentifier("idea.loading")
        case .gone:
            EmptyState(icon: "eye.slash", title: L10n.text(K.social.feed.ideaGone))
                .accessibilityIdentifier("idea.gone")
        case .failed(let failure):
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: failure.message)
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                VButton(L10n.text(K.social.feed.retry), tid: "idea.retry", role: .secondary) { Task { await model.load() } }
            }
            .accessibilityIdentifier("idea.failed")
        case .loaded:
            if let idea = model.idea { loaded(idea) }
        }
    }

    @ViewBuilder private func loaded(_ idea: Idea) -> some View {
        IdeaCardView(
            idea: idea,
            state: IdeaCardState(
                isDetail: true, failure: model.actionFailure, savedNote: model.savedNote, commentsOpen: model.commentsOpen),
            actions: IdeaCardActions(
                like: { Task { await model.toggleLike() } },
                save: { Task { await model.save() } },
                comments: { model.commentsOpen.toggle() },
                report: { if let report = model.reportModel() { reporting = ReportItem(model: report) } },
                block: { confirmBlock = true },
                delete: { confirmDelete = true }),
            tidPrefix: "idea")
        if model.commentsOpen && idea.status.isPublished {
            CommentsView(model: commentsModel(for: idea)) { comment in
                reporting = ReportItem(model: model.reportModel(commentID: comment.id))
            }
        }
    }

    /// The comments model knows whether the viewer wrote the idea only once the idea is loaded.
    private func commentsModel(for idea: Idea) -> CommentsModel {
        if comments.ideaMine != idea.mine {
            comments = CommentsModel(
                env: env, ideaID: idea.id, ideaMine: idea.mine, onCount: { [model] in model.commentCountChanged($0) })
        }
        return comments
    }
}
