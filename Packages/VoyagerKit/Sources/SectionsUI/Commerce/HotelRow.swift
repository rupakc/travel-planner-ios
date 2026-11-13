import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// One hotel: name and place, nightly price (the AI estimate is labelled), stars, amenities, then
/// Add to plan / Book / Watch.
struct HotelRow: View {
    let hotel: JSONValue
    let ctx: SectionContext

    private var item: SectionItem { SectionItem(hotel) }

    /// Hotel prices come from the hotel agent unless the backend says otherwise; the watch needs a live look, so
    /// the button is shown for any dated single-city stay and the server answers `no_live_price` when it has none.
    static func watchSpec(for hotel: JSONValue, search: JSONValue?, now: Date = Date()) -> JSONValue? {
        WatchSpecs.hotel(hotel, search: search, now: now)
    }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: item.name ?? "")
                            .font(VFont.body(.subheadline, weight: .semibold))
                            .foregroundStyle(SemanticColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let place = hotel["location"].string, !place.isEmpty {
                            Text(verbatim: place).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        }
                    }
                    Spacer(minLength: Spacing.sm)
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        if let nightly = hotel["price_per_night_usd"].double, nightly.isFinite {
                            Text(verbatim: Fmt.currency(nightly, code: "USD") + L10n.text(K.results.hotels.perNight))
                                .font(VFont.body(.headline, weight: .semibold))
                                .foregroundStyle(SemanticColor.text)
                                // The price stays on one line (it shrinks a little before it would wrap); the name wraps instead.
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        if let total = hotel["total_price_usd"].double, total.isFinite, total > 0 {
                            Text(verbatim: L10n.text(K.results.total, ["amount": Fmt.currency(total, code: "USD")]))
                                .font(VFont.body(.caption))
                                .foregroundStyle(SemanticColor.textMuted)
                        }
                        if item.isEstimate { EstimateLabel() }
                    }
                }
                HStack(spacing: Spacing.sm) {
                    if let stars = hotel["star_rating"].double, stars.isFinite, stars > 0 {
                        Text(verbatim: String(repeating: "★", count: min(5, Commerce.clampedInt(stars.rounded()) ?? 0)))
                            .font(VFont.body(.caption))
                            .foregroundStyle(Palette.color(.amber, .s600))
                            .accessibilityLabel(Text(verbatim: Fmt.number(stars, fractionDigits: 0) + " ★"))
                    }
                    if let score = hotel["review_score"].double, score.isFinite {
                        Text(verbatim: Fmt.number(score, fractionDigits: 1) + "/10")
                            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                    }
                    if let source = hotel["source"].string, !source.isEmpty { CommerceTag(text: source, family: .violet) }
                }
                let amenities = (hotel["amenities"].array ?? []).compactMap(\.string)
                if !amenities.isEmpty {
                    Text(verbatim: amenities.prefix(4).joined(separator: " · ") + (amenities.count > 4 ? " +\(amenities.count - 4)" : ""))
                        .font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RowActions(
                    tidPrefix: "results.hotel", selected: ctx.isSelected("hotel", hotel),
                    toggle: { ctx.toggle("hotel", hotel) }, bookURL: item.bookingURL, section: "hotels",
                    watch: Self.watchSpec(for: hotel, search: ctx.searchData).map {
                        WatchButton(
                            kind: .hotel, spec: $0, tid: "results.hotel.watch", title: L10n.text(K.alerts.btn.watchPrice),
                            accessibilityName: L10n.text(K.alerts.btn.watchHotelAria, ["name": item.name ?? ""]), ctx: ctx)
                    })
            }
        }
        .accessibilityElement(children: .contain)
    }
}
