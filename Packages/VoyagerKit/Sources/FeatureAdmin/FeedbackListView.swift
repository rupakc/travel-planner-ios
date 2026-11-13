import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Feedback entries with page, category and minimum-rating filters.
struct FeedbackListView: View {
    let model: AdminFeedbackModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                filters
                if let error = model.error {
                    ErrorState(error: error) { Task { await model.load() } }
                } else if model.loading && !model.loaded {
                    Text(verbatim: L10n.text(K.account.admin.common.loading)).foregroundStyle(SemanticColor.textMuted)
                } else if model.entries.isEmpty {
                    EmptyState(icon: "bubble.left", title: L10n.text(K.account.admin.feedback.empty))
                } else {
                    VStack(spacing: Spacing.sm) {
                        ForEach(Array(model.entries.enumerated()), id: \.offset) { _, entry in row(entry) }
                    }
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .refreshable { await model.load() }
        .task(id: model.filterKey) { await model.load() }
        .accessibilityIdentifier("admin.feedback.list")
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            group(K.account.admin.feedback.page) {
                chip(L10n.text(K.account.admin.feedback.all), "page.all", model.page == nil) { model.page = nil }
                ForEach(AdminFeedbackModel.pages, id: \.self) { id in
                    chip(Self.pageTitle(id), "page.\(id)", model.page == id) { model.page = id }
                }
            }
            group(K.account.admin.feedback.category) {
                chip(L10n.text(K.account.admin.feedback.all), "cat.all", model.category == nil) { model.category = nil }
                ForEach(AdminFeedbackModel.categories, id: \.self) { id in
                    chip(Self.categoryTitle(id), "cat.\(id)", model.category == id) { model.category = id }
                }
            }
            group(K.account.admin.feedback.minRating) {
                chip(L10n.text(K.account.admin.feedback.any), "rating.any", model.minRating == nil) { model.minRating = nil }
                ForEach(AdminFeedbackModel.ratings, id: \.self) { stars in
                    chip("\(stars)+", "rating.\(stars)", model.minRating == stars) { model.minRating = stars }
                }
            }
        }
    }

    private func chip(_ title: String, _ tid: String, _ selected: Bool, _ action: @escaping () -> Void) -> some View {
        VChip(title: title, tid: "admin.feedback.\(tid)", selected: selected, action: action)
    }

    private func group<Chips: View>(_ title: LKey, @ViewBuilder _ chips: () -> Chips) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(title)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            ChipFlow(spacing: Spacing.sm) { chips() }
        }
    }

    private func row(_ entry: FeedbackEntry) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(verbatim: Self.stars(entry.rating)).foregroundStyle(SemanticColor.accent)
                    Spacer(minLength: Spacing.sm)
                    let kind = [entry.page, entry.category.map(Self.categoryTitle)].compactMap { $0 }
                    Text(verbatim: kind.joined(separator: " / "))
                        .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                }
                if let message = entry.message, !message.isEmpty {
                    Text(verbatim: message).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                }
                let who = [entry.username, entry.createdAt.map { String($0.prefix(10)) }].compactMap { $0 }
                Text(verbatim: who.joined(separator: " · "))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    /// Always within 0...5, whatever the backend sent.
    static func stars(_ rating: Int?) -> String {
        let value = min(max(rating ?? 0, 0), 5)
        return String(repeating: "★", count: value) + String(repeating: "☆", count: 5 - value)
    }

    static func pageTitle(_ id: String) -> String {
        switch id {
        case "search": L10n.text(K.account.admin.feedback.pages.search)
        case "results": L10n.text(K.account.admin.feedback.pages.results)
        case "chat": L10n.text(K.account.admin.feedback.pages.chat)
        case "preferences": L10n.text(K.account.admin.feedback.pages.preferences)
        default: L10n.text(K.account.admin.feedback.pages.admin)
        }
    }

    static func categoryTitle(_ id: String) -> String {
        switch id {
        case "bug": L10n.text(K.account.admin.feedback.categories.bug)
        case "feature_request": L10n.text(K.account.admin.feedback.categories.feature_request)
        case "praise": L10n.text(K.account.admin.feedback.categories.praise)
        default: L10n.text(K.account.admin.feedback.categories.general)
        }
    }
}

/// Chips that wrap onto further lines.
struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
