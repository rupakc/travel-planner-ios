import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Places to see (api-contract 3.4.5): category, neighbourhood, rating, visit time, admission, highlights.
public struct PlacesSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let places = Info.list(data, "results")
        if places.isEmpty {
            InfoEmpty(key: K.results.places.none)
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(Array(places.enumerated()), id: \.offset) { _, place in card(place) }
            }
        }
    }

    private func card(_ place: JSONValue) -> some View {
        let item = SectionItem(place)
        return VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: item.name ?? "")
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.sm) {
                    if let category = Info.text(place["category"]) { InfoTag(title: category, family: .teal) }
                    if place["hidden_gem"].bool == true { InfoTag(title: L10n.text(K.results.tags.hiddenGem), family: .violet) }
                    if place["family_friendly"].bool == true { InfoTag(title: L10n.text(K.results.tags.family), family: .sky) }
                    if place["wheelchair_accessible"].bool == true {
                        InfoTag(title: L10n.text(K.results.tags.accessible), family: .emerald)
                    }
                }
                InfoLine(label: nil, value: Info.text(place["neighbourhood"]))
                InfoLine(label: nil, value: Info.text(place["description"]))
                HStack(spacing: Spacing.md) {
                    if let rating = item.rating {
                        Text(verbatim: "★ " + Fmt.number(rating, fractionDigits: 1))
                    }
                    if let hours = place["visit_duration_hours"].double {
                        Text(verbatim: L10n.text(K.results.places.approxHours, ["h": Fmt.number(hours, fractionDigits: 1)]))
                    }
                    if let fee = place["admission_fee_usd"].double {
                        Text(verbatim: fee == 0 ? L10n.text(K.results.places.freeEntry) : Fmt.currency(fee, code: "USD"))
                    }
                }
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
                InfoLine(label: nil, value: Info.text(place["best_time_to_visit"]))
                let highlights = Info.texts(place["highlights"])
                if !highlights.isEmpty { InfoBullets(items: highlights) }
                HStack {
                    InfoLink(
                        title: L10n.text(K.results.places.viewDetails), url: Info.httpsURL(place["info_url"]),
                        section: "places_to_see", ctx: ctx)
                    Spacer(minLength: 0)
                    PlanToggle(field: "places_to_see", item: place, ctx: ctx)
                }
            }
        }
    }
}
