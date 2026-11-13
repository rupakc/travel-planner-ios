import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// One leg of a flight: route, times, duration, stops and layovers.
struct FlightLegView: View {
    /// `Depart` / `Return`, or nil inside a multi-city leg.
    let title: String?
    let leg: JSONValue

    static func stopsText(_ stops: Int) -> String {
        stops <= 0 ? L10n.text(K.results.flights.direct) : L10n.text(K.results.flights.stops, count: stops)
    }

    static func durationText(_ minutes: Double?) -> String? {
        guard let (hours, rest) = Commerce.hoursMinutes(minutes) else { return nil }
        return L10n.text(K.results.flights.duration, ["h": String(hours), "min": String(rest)])
    }

    static func layoverText(_ layover: JSONValue) -> String? {
        let place = layover["city"].string ?? layover["airport"].string
        guard let place, !place.isEmpty else { return nil }
        guard let hours = layover["duration_hours"].double, hours.isFinite, hours > 0 else {
            return L10n.text(K.results.flights.stopIn, ["place": place])
        }
        return L10n.text(K.results.flights.layoverIn, ["hours": Commerce.compact(hours), "place": place])
    }

    private var route: String? {
        let from = leg["origin"].string ?? ""
        let to = leg["destination"].string ?? ""
        return from.isEmpty && to.isEmpty ? nil : "\(from) → \(to)"
    }

    private var times: String? {
        let depart = leg["departure_time"].string ?? ""
        let arrive = leg["arrival_time"].string ?? ""
        let date = leg["departure_date"].string ?? ""
        let span = depart.isEmpty && arrive.isEmpty ? "" : "\(depart) → \(arrive)"
        let text = [date, span].filter { !$0.isEmpty }.joined(separator: "  ")
        return text.isEmpty ? nil : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let title {
                Text(verbatim: title)
                    .font(VFont.body(.caption, weight: .semibold))
                    .foregroundStyle(SemanticColor.textMuted)
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                if let airline = leg["airline"].string, !airline.isEmpty {
                    Text(verbatim: [airline, leg["flight_number"].string].compactMap { $0 }.joined(separator: " "))
                        .font(VFont.body(.subheadline, weight: .semibold))
                        .foregroundStyle(SemanticColor.text)
                }
            }
            if let route {
                Text(verbatim: route).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            }
            if let times {
                Text(verbatim: times).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
            Text(verbatim: summary)
                .font(VFont.body(.caption))
                .foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array((leg["layovers"].array ?? []).compactMap(Self.layoverText).enumerated()), id: \.offset) { _, text in
                Text(verbatim: text).font(VFont.body(.caption)).foregroundStyle(Palette.color(.amber, .s700))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        [Self.durationText(leg["duration_minutes"].double), Self.stopsText(leg["stops"].int ?? 0)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
