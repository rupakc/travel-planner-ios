import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// One flight fare: price (estimates are labelled), outbound and return legs, then Add to plan / Book / Watch.
/// Watch is hidden for an estimate, a multi-city trip and a past departure, as on the web.
struct FlightRow: View {
    let flight: JSONValue
    let ctx: SectionContext

    private var item: SectionItem { SectionItem(flight) }

    static func watchSpec(for flight: JSONValue, search: JSONValue?, now: Date = Date()) -> JSONValue? {
        SectionItem(flight).isEstimate ? nil : WatchSpecs.fare(search: search, now: now)
    }

    private var tripTypeKey: LKey {
        flight["trip_type"].string == "one_way" ? K.results.flights.oneWay : K.results.flights.roundTripPerPerson
    }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        PriceText(amount: item.priceUSD, currency: "USD", estimate: item.isEstimate)
                        Text(verbatim: L10n.text(tripTypeKey))
                            .font(VFont.body(.caption))
                            .foregroundStyle(SemanticColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Spacing.sm)
                    if flight["source"].string == "google_flights" {
                        CommerceTag(text: "Google Flights", family: .sky)
                    }
                }
                FlightLegView(title: flight["return"].isTruthy ? L10n.text(K.results.flights.depart) : nil, leg: flight["outbound"])
                if flight["return"].isTruthy {
                    FlightLegView(title: L10n.text(K.results.flights.return), leg: flight["return"])
                }
                RowActions(
                    tidPrefix: "results.flight", selected: ctx.isSelected("flights", flight),
                    toggle: { ctx.toggle("flights", flight) }, bookURL: item.bookingURL, section: "flights",
                    watch: Self.watchSpec(for: flight, search: ctx.searchData).map {
                        WatchButton(
                            kind: .flight, spec: $0, tid: "results.flight.watch", title: L10n.text(K.alerts.btn.watchFare),
                            accessibilityName: L10n.text(K.alerts.btn.watchFare), ctx: ctx)
                    })
            }
        }
        .accessibilityElement(children: .contain)
    }
}
