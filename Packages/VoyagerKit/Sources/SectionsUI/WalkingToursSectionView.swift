import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Free walking tours (api-contract 3.4.6): image (at most 120 pt), provider, rating, duration, reason.
public struct WalkingToursSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    /// The image box: never larger than this, so a card stays compact at any Dynamic Type size.
    static let imageSide: CGFloat = 120

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let tours = Info.list(data, "results")
        if tours.isEmpty {
            InfoEmpty(key: K.sections.page.noResults)
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(Array(tours.enumerated()), id: \.offset) { _, tour in card(tour) }
            }
        }
    }

    private func card(_ tour: JSONValue) -> some View {
        let item = SectionItem(tour)
        let side = Self.imageSide
        return VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let image = Info.httpsURL(tour["image_url"]) {
                    RemoteImage(url: image, targetSize: CGSize(width: side, height: side))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.input))
                        .accessibilityHidden(true)
                }
                Text(verbatim: item.name ?? "")
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.sm) {
                    if tour["top_pick"].bool == true { InfoTag(title: "★", family: .amber, accessibilityText: "top pick") }
                    if let provider = Info.text(tour["provider"]) { InfoTag(title: provider, family: .teal) }
                }
                HStack(spacing: Spacing.md) {
                    if let rating = item.rating { Text(verbatim: "★ " + Fmt.number(rating, fractionDigits: 1)) }
                    if let duration = Info.text(tour["duration"]) { Text(verbatim: duration) }
                    if let price = Info.text(tour["price_note"]) { Text(verbatim: price) }
                }
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
                InfoLine(label: nil, value: Info.text(tour["reason"]) ?? Info.text(tour["description"]))
                HStack {
                    InfoLink(
                        title: L10n.text(K.results.transport.moreInfo), url: item.bookingURL, section: "walking_tours",
                        ctx: ctx)
                    Spacer(minLength: 0)
                    PlanToggle(field: "walking_tours", item: tour, ctx: ctx)
                }
            }
        }
    }
}
