import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The weekly leaderboard on the Play hub: scope (friends or global), week (this or last), the rows (handles only), the
/// caller's own standing, and on the global board the opt-in card.
struct BoardSectionView: View {
    let model: BoardModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.play.board.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityAddTraits(.isHeader)
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.sm) { scopeChips }
                        VStack(alignment: .leading, spacing: Spacing.sm) { scopeChips }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text(verbatim: L10n.text(K.play.board.scope)))
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.sm) { weekChips }
                        VStack(alignment: .leading, spacing: Spacing.sm) { weekChips }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    content
                }
            }
        }
        .accessibilityIdentifier("play.board")
    }

    @ViewBuilder private var scopeChips: some View {
        ForEach(BoardScope.allCases, id: \.self) { scope in
            VChip(
                title: scope == .global ? L10n.text(K.play.board.scope_global) : L10n.text(K.play.board.scope_friends),
                tid: "play.board.scope.\(scope.rawValue)", selected: model.scope == scope
            ) { Task { await model.select(scope: scope) } }
        }
    }

    @ViewBuilder private var weekChips: some View {
        ForEach(BoardWeek.allCases, id: \.self) { week in
            VChip(
                title: week == .current ? L10n.text(K.play.board.week_current) : L10n.text(K.play.board.week_previous),
                tid: "play.board.week.\(week.rawValue)", selected: model.week == week
            ) { Task { await model.select(week: week) } }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.play.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.md)
        case .failed:
            Text(verbatim: L10n.text(K.play.board.failed)).font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("play.board.failed")
        case .loaded:
            loaded
        }
    }

    @ViewBuilder private var loaded: some View {
        optInCard
        if model.rows.isEmpty {
            Text(verbatim: L10n.text(K.play.board.empty)).font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("play.board.empty")
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(model.rows) { row in BoardRowView(model: model, row: row) }
            }
            .accessibilityIdentifier("play.board.rows")
        }
        if let text = model.mineText {
            Text(verbatim: text).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.board.mine")
        } else if model.showsPrivateProfileNote {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.play.board.profilePrivate)).font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("play.board.profile-private")
                VButton(L10n.text(K.social.profile.edit), tid: "play.board.edit-profile", role: .secondary) { model.createProfile() }
            }
        } else if model.showsUnranked {
            Text(verbatim: L10n.text(K.play.board.unranked)).font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("play.board.unranked")
        }
    }

    @ViewBuilder private var optInCard: some View {
        switch model.optIn {
        case .none:
            EmptyView()
        case .join, .needsProfile:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.play.board.optinNote)).font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.text).fixedSize(horizontal: false, vertical: true)
                if let text = model.errorText {
                    Text(verbatim: text).font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.destructive)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.board.error")
                }
                if model.optIn == .join {
                    VButton(L10n.text(K.play.board.join), tid: "play.board.join") { Task { await model.join() } }
                        .disabled(model.joining)
                } else {
                    VButton(L10n.text(K.social.feed.createProfile), tid: "play.board.createProfile") {
                        model.createProfile()
                    }
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .borderedSurface(
                RoundedRectangle(cornerRadius: Radius.itemCard), fill: SemanticColor.surface, border: SemanticColor.border)
            .accessibilityIdentifier("play.board.optin")
        }
    }
}

/// One board row: rank, handle (verbatim), the level only when the user opted in to show it, and the week's points.
private struct BoardRowView: View {
    let model: BoardModel
    let row: BoardRow

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                name
                Spacer(minLength: Spacing.sm)
                points.multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                name
                points
            }
        }
        // A handle is one unbreakable word: capped so it never breaks mid-word at the largest sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(row.isYou ? "play.board.row.you" : "play.board.row")
    }

    private var name: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.line(row)).font(VFont.body(.subheadline, weight: row.isYou ? .bold : .semibold))
                .foregroundStyle(row.isYou ? SemanticColor.primary : SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
            if let level = model.level(row) {
                Text(verbatim: level).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    private var points: some View {
        Text(verbatim: L10n.text(K.play.board.points, count: row.score)).font(VFont.body(.subheadline))
            .foregroundStyle(SemanticColor.textMuted).fixedSize(horizontal: false, vertical: true)
    }
}
