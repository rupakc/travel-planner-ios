import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// One link in My shares: what it is, when it was made, its URL and the actions. "Stop sharing" first asks, inline, and
/// says it is immediate.
struct ShareRow: View {
    let item: MyShareItem
    let model: MySharesModel

    private var isConfirming: Bool { model.confirming == item.id }
    private var isRevoking: Bool { model.revoking.contains(item.id) }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                header
                Text(verbatim: item.title.isEmpty ? L10n.text(K.share.mine.untitled) : item.title)
                    .font(VFont.body(.headline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shares.title")
                Text(verbatim: item.url)
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    .lineLimit(1).truncationMode(.middle)
                if isConfirming { confirmation } else { actions }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shares.row")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            if let label = kindLabel {
                Text(verbatim: label)
                    .font(VFont.body(.caption, weight: .semibold)).foregroundStyle(SemanticColor.text)
                    .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                    .borderedSurface(Capsule(), fill: SemanticColor.surface, border: SemanticColor.border)
            }
            if let created = item.createdAt {
                Text(verbatim: L10n.text(K.share.mine.created, ["date": Fmt.date(created)]))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    private var kindLabel: String? {
        switch item.kind {
        case .plan: L10n.text(K.share.mine.kind.plan)
        case .recap: L10n.text(K.share.mine.kind.recap)
        case .savings: L10n.text(K.share.mine.kind.savings)
        case .quiz: L10n.text(K.share.titleKind.quiz)
        case .status: L10n.text(K.share.titleKind.status)
        case .unknown: nil
        }
    }

    // MARK: Actions

    private var actions: some View {
        ActionWrap(spacing: Spacing.sm) {
            VButton(L10n.text(K.share.mine.copy), tid: "shares.copy", role: .secondary) {
                model.copy(item)
            }
            if item.token != nil {
                VButton(L10n.text(K.share.mine.open), tid: "shares.open", role: .secondary) {
                    model.open(item)
                }
            }
            if item.target != nil {
                VButton(L10n.text(K.share.mine.shareAgain), tid: "shares.again", role: .secondary) {
                    model.shareAgain(item)
                }
            }
            VButton(L10n.text(K.share.mine.revoke), tid: "shares.revoke", role: .secondary) {
                model.askRevoke(item)
            }
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.share.mine.confirm))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shares.confirm")
            ActionWrap(spacing: Spacing.sm) {
                VButton(L10n.text(K.share.mine.yes), tid: "shares.revoke-yes", role: .destructive) {
                    Task { await model.confirmRevoke(item) }
                }
                .disabled(isRevoking)
                VButton(L10n.text(K.share.mine.no), tid: "shares.revoke-no", role: .secondary) {
                    model.cancelRevoke()
                }
                if isRevoking { ProgressView().accessibilityHidden(true) }
            }
        }
    }
}
