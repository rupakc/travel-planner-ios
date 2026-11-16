import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The comments of an idea and the box to add one. Every comment is a verbatim `Text`.
struct CommentsView: View {
    @Bindable var model: CommentsModel
    var onReport: (IdeaComment) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: L10n.text(K.social.comments.title))
                .font(VFont.body(.headline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            list
            if let failure = model.failure {
                Text(verbatim: failure.message)
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("comments.error")
            }
            composer
        }
        .task { await model.start() }
        .accessibilityIdentifier("comments.root")
    }

    @ViewBuilder private var list: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("comments.loading")
        case .failed(let failure):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: failure.message)
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                VButton(L10n.text(K.social.feed.retry), tid: "comments.retry", role: .secondary) {
                    Task { await model.load() }
                }
            }
        case .loaded:
            if model.isEmpty {
                Text(verbatim: L10n.text(K.social.comments.empty))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    .accessibilityIdentifier("comments.empty")
            }
            ForEach(model.visible) { comment in row(comment) }
            if model.next != nil {
                VButton(L10n.text(K.social.comments.more), tid: "comments.more", role: .secondary) {
                    Task { await model.loadMore() }
                }
            }
        }
    }

    private func row(_ comment: IdeaComment) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) { rowBadges(comment) }
                VStack(alignment: .leading, spacing: Spacing.xs) { rowBadges(comment) }
            }
            Text(verbatim: comment.text)
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) { rowActions(comment) }
                VStack(alignment: .leading, spacing: Spacing.xs) { rowActions(comment) }
            }
        }
        .padding(.bottom, Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment.row")
    }

    @ViewBuilder private func rowBadges(_ comment: IdeaComment) -> some View {
        Text(verbatim: "@" + comment.authorHandle)
            .font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.text)
        if comment.helpful { pill(L10n.text(K.social.comments.helpful), tid: "comment.helpful") }
        if comment.status == .held { pill(L10n.text(K.social.comments.held), tid: "comment.held") }
    }

    private func pill(_ text: String, tid: String) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.caption, weight: .medium)).foregroundStyle(SemanticColor.text)
            .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
            .borderedSurface(Capsule(), fill: SemanticColor.surface, border: SemanticColor.border)
            .accessibilityIdentifier(tid)
    }

    @ViewBuilder private func rowActions(_ comment: IdeaComment) -> some View {
        if model.canMarkHelpful(comment) {
            linkButton(
                L10n.text(comment.helpful ? K.social.comments.unmarkHelpful : K.social.comments.markHelpful),
                tid: "comment.helpful-toggle"
            ) { Task { await model.toggleHelpful(comment) } }
        }
        if model.canDelete(comment) {
            linkButton(L10n.text(K.social.comments.delete), tid: "comment.delete") { Task { await model.delete(comment) } }
        }
        if model.canReport(comment) {
            linkButton(L10n.text(K.social.idea.report), tid: "comment.report") { onReport(comment) }
        }
    }

    private func linkButton(_ title: String, tid: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(VFont.body(.footnote, weight: .medium)).foregroundStyle(SemanticColor.primary)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tid)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.social.comments.label))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            TextField("", text: $model.draft, axis: .vertical)
                .lineLimit(2...5)
                .font(VFont.body(.subheadline))
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .padding(Spacing.sm)
                .borderedSurface(RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
                .accessibilityLabel(Text(verbatim: L10n.text(K.social.comments.label)))
                .accessibilityIdentifier("comments.input")
            Text(verbatim: L10n.text(
                K.social.comments.counter, ["n": String(model.draft.count), "max": String(CommentsModel.maxLength)]))
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            VButton(L10n.text(K.social.comments.post), tid: "comments.post") { Task { await model.post() } }
                .disabled(!model.canPost)
        }
    }
}
