import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The body of a recap or savings share: a tag, the server's headline, destination and month, the owner's name when
/// the sharer allowed it, the counts-only stats, and a way to plan one's own trip. Everything shown comes from the
/// public `card`; nothing is computed here.
struct SharedCardBody: View {
    let tag: LKey
    let headline: String
    let card: SharedCard
    let ownerName: String?
    let onPlanOwn: () -> Void

    /// The stat keys the app knows; any other key from a newer server is ignored.
    static func label(for key: String) -> LKey? {
        switch key {
        case "activities": K.share.page.stat.activities
        case "hotels": K.share.page.stat.hotels
        case "places": K.share.page.stat.places
        case "places_visited": K.share.page.stat.places_visited
        case "countries": K.share.page.stat.countries
        case "drops_caught": K.share.page.stat.drops_caught
        case "targets_hit": K.share.page.stat.targets_hit
        case "correct": K.share.page.stat.correct
        default: nil
        }
    }

    /// Known keys with a positive count, in the server's order (counts only: never money, dates or names).
    static func visibleStats(_ card: SharedCard) -> [(label: LKey, count: Int)] {
        card.stats.compactMap { stat in
            guard stat.count > 0, let label = label(for: stat.key) else { return nil }
            return (label, stat.count)
        }
    }

    private var subtitle: String? {
        let parts = [card.destination, card.period].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: L10n.text(tag).uppercased())
                        .font(VFont.body(.caption, weight: .semibold))
                        .foregroundStyle(SemanticColor.primary)
                    Text(verbatim: headline)
                        .font(VFont.display(.title))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(VFont.body(.subheadline))
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                    if let ownerName {
                        Text(verbatim: L10n.text(K.share.page.byline, ["name": ownerName]))
                            .font(VFont.body(.footnote))
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
            let stats = Self.visibleStats(card)
            if !stats.isEmpty {
                VCard {
                    VStack(spacing: Spacing.sm) {
                        ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: L10n.text(stat.label))
                                    .font(VFont.body(.subheadline))
                                    .foregroundStyle(SemanticColor.textMuted)
                                Spacer(minLength: Spacing.md)
                                Text(verbatim: "\(stat.count)")
                                    .font(VFont.display(.title3))
                                    .foregroundStyle(SemanticColor.text)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            VButton(L10n.text(K.share.page.cta), tid: "share.planOwn", role: .primary, action: onPlanOwn)
                .frame(maxWidth: .infinity)
        }
    }
}
