import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// What the card shows besides the idea itself.
struct IdeaCardState: Equatable {
    /// The detail screen: the title is plain text, all items are listed.
    var isDetail = false
    var failure: IdeaFailure?
    var savedNote = false
    var commentsOpen = false
}

struct IdeaCardActions {
    var open: () -> Void = {}
    var like: () -> Void = {}
    var save: () -> Void = {}
    var comments: () -> Void = {}
    var report: () -> Void = {}
    var block: () -> Void = {}
    var delete: () -> Void = {}
}

/// One idea. Every user string (handle, title, caption, item names) is a verbatim `Text`: no markdown, no links and no
/// data detectors (plan ruling R13), so hostile text shows as typed.
struct IdeaCardView: View {
    let idea: Idea
    var state = IdeaCardState()
    var actions = IdeaCardActions()
    var tidPrefix = "idea"

    private var facts: IdeaFacts { IdeaFacts(snapshot: idea.snapshot) }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                titleView
                if !idea.caption.isEmpty {
                    Text(verbatim: idea.caption)
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(tidPrefix).caption")
                }
                factsView
                itemsView
                actionRow
                if state.savedNote {
                    Text(verbatim: L10n.text(K.social.idea.savedNote))
                        .font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(tidPrefix).saved-note")
                }
                if let failure = state.failure {
                    Text(verbatim: failure.message)
                        .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("\(tidPrefix).error")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(tidPrefix).card")
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(K.social.idea.by) + " @" + idea.author.handle)
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(tidPrefix).author")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm) { badges }
                VStack(alignment: .leading, spacing: Spacing.xs) { badges }
            }
        }
    }

    @ViewBuilder private var badges: some View {
        badge(kindTitle, tid: "\(tidPrefix).kind")
        if idea.status == .held && idea.mine {
            badge(L10n.text(K.social.idea.held), tid: "\(tidPrefix).held", highlighted: true)
        }
    }

    private var kindTitle: String {
        L10n.text(idea.kind == .recap ? K.social.idea.kind.recap : K.social.idea.kind.plan)
    }

    private func badge(_ text: String, tid: String, highlighted: Bool = false) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.caption, weight: .medium))
            .foregroundStyle(highlighted ? SemanticColor.onPrimary : SemanticColor.text)
            .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
            .borderedSurface(
                Capsule(), fill: highlighted ? SemanticColor.primary : SemanticColor.surface,
                border: highlighted ? nil : SemanticColor.border)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(tid)
    }

    @ViewBuilder private var titleView: some View {
        let title = Text(verbatim: idea.title)
            .font(VFont.body(.headline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        if state.isDetail {
            title.accessibilityAddTraits(.isHeader).accessibilityIdentifier("\(tidPrefix).title")
        } else {
            Button(action: actions.open) {
                title.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(tidPrefix).open")
        }
    }

    @ViewBuilder private var factsView: some View {
        if !(facts.destinations.isEmpty && facts.days == 0 && facts.stats.isEmpty) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if !facts.destinations.isEmpty {
                    Text(verbatim: facts.destinations.joined(separator: " · "))
                }
                if facts.days > 0 {
                    Text(verbatim: L10n.text(K.social.idea.tripDays, ["days": String(facts.days)]))
                }
                ForEach(facts.stats, id: \.key) { stat in
                    Text(verbatim: statTitle(stat.key) + " " + String(stat.count))
                }
            }
            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(tidPrefix).facts")
        }
    }

    private func statTitle(_ key: IdeaFacts.Stat.Key) -> String {
        switch key {
        case .activities: L10n.text(K.social.idea.stats.activities)
        case .hotels: L10n.text(K.social.idea.stats.hotels)
        case .places: L10n.text(K.social.idea.stats.places)
        }
    }

    @ViewBuilder private var itemsView: some View {
        let names = state.isDetail ? facts.itemNames : facts.shown
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.social.idea.itemsHeading))
                    .font(VFont.body(.caption, weight: .semibold)).foregroundStyle(SemanticColor.textMuted)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Text(verbatim: "•").accessibilityHidden(true)
                        Text(verbatim: name).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                }
                if !state.isDetail && facts.hiddenCount > 0 {
                    Text(verbatim: L10n.text(K.social.idea.moreItems, ["n": String(facts.hiddenCount)]))
                        .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                }
            }
            .accessibilityIdentifier("\(tidPrefix).items")
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        SocialActionWrap(spacing: Spacing.sm) { buttons }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder private var buttons: some View {
        actionButton(
            icon: idea.liked ? "heart.fill" : "heart",
            title: L10n.text(idea.liked ? K.social.idea.unlike : K.social.idea.like), count: idea.likes,
            tid: "\(tidPrefix).like", selected: idea.liked, action: actions.like)
        if !idea.mine && idea.status.isPublished {
            actionButton(
                icon: idea.saved ? "bookmark.fill" : "bookmark",
                title: L10n.text(idea.saved ? K.social.idea.savedAgain : K.social.idea.save), count: nil,
                tid: "\(tidPrefix).save", selected: idea.saved, action: actions.save)
        }
        if idea.status.isPublished {
            actionButton(
                icon: "bubble.left",
                title: L10n.text(state.commentsOpen ? K.social.idea.hideComments : K.social.idea.comments),
                count: idea.comments, tid: "\(tidPrefix).comments", selected: state.commentsOpen, action: actions.comments)
        }
        moreMenu
    }

    private func actionButton(
        icon: String, title: String, count: Int?, tid: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon).accessibilityHidden(true)
                Text(verbatim: title).fixedSize(horizontal: false, vertical: true)
                if let count { Text(verbatim: String(count)) }
            }
            .font(VFont.body(.subheadline, weight: .medium))
            .foregroundStyle(SemanticColor.text)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 44)
            .borderedSurface(Capsule(), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(tid)
    }

    @ViewBuilder private var moreMenu: some View {
        if idea.mine {
            Menu {
                Button(role: .destructive, action: actions.delete) {
                    Label(L10n.text(K.social.idea.delete), systemImage: "trash")
                }
            } label: { ellipsis }
            .accessibilityLabel(Text(verbatim: L10n.text(K.social.idea.delete)))
            .accessibilityIdentifier("\(tidPrefix).more")
        } else {
            Menu {
                Button(action: actions.report) {
                    Label(L10n.text(K.social.idea.report), systemImage: "flag")
                }
                Button(role: .destructive, action: actions.block) {
                    Label(L10n.text(K.social.block.block), systemImage: "hand.raised")
                }
            } label: { ellipsis }
            .accessibilityLabel(Text(verbatim: L10n.text(K.social.idea.report)))
            .accessibilityIdentifier("\(tidPrefix).more")
        }
    }

    private var ellipsis: some View {
        Image(systemName: "ellipsis")
            .font(VFont.body(.subheadline, weight: .medium))
            .foregroundStyle(SemanticColor.text)
            .frame(minWidth: 44, minHeight: 44)
            .borderedSurface(Capsule(), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
            .contentShape(Capsule())
    }
}
