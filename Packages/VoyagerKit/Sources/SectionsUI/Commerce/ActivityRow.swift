import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// One activity. Items from the user's link carry the "From your link" badge. Prices are labelled estimates
/// unless the source is a booking site's own listing.
struct ActivityRow: View {
    let activity: JSONValue
    let ctx: SectionContext

    private var item: SectionItem { SectionItem(activity) }

    static func watchSpec(for activity: JSONValue, search: JSONValue?) -> JSONValue? {
        WatchSpecs.activity(activity, search: search)
    }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if activity["from_link"].isTruthy {
                    CommerceTag(text: L10n.text(K.misc.fromLink.chip), family: .teal)
                }
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text(verbatim: item.name ?? "")
                        .font(VFont.body(.subheadline, weight: .semibold))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm)
                    if item.priceUSD != nil { PriceText(amount: item.priceUSD, currency: "USD", estimate: item.isEstimate) }
                }
                if let text = activity["description"].string, !text.isEmpty {
                    Text(verbatim: text).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                facts
                RowActions(
                    tidPrefix: "results.activity", selected: ctx.isSelected("activities", activity),
                    toggle: { ctx.toggle("activities", activity) }, bookURL: item.bookingURL, section: "activities",
                    watch: watchButton)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var watchButton: WatchButton? {
        guard !item.isEstimate, let spec = Self.watchSpec(for: activity, search: ctx.searchData) else { return nil }
        return WatchButton(
            kind: .activity, spec: spec, tid: "results.activity.watch", title: L10n.text(K.alerts.btn.watchPrice),
            accessibilityName: L10n.text(K.alerts.btn.watchActivityAria, ["name": item.name ?? ""]), ctx: ctx)
    }

    private var facts: some View {
        HStack(spacing: Spacing.sm) {
            if let rating = item.rating {
                Text(verbatim: "★ " + Fmt.number(rating, fractionDigits: 1)).font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.textMuted)
            }
            if let hours = activity["duration_hours"].double, hours.isFinite, hours > 0 {
                Text(verbatim: L10n.text(K.results.activities.hours, ["h": Commerce.compact(hours)]))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
            if let score = activity["similarity_score"].double, score.isFinite, (0...1).contains(score) {
                let percent = String(Int((score * 100).rounded()))
                CommerceTag(text: L10n.text(K.results.activities.match, ["percent": percent]), family: .emerald)
            }
            if activity["hidden_gem"].bool == true { CommerceTag(text: L10n.text(K.results.tags.hiddenGem), family: .amber) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
