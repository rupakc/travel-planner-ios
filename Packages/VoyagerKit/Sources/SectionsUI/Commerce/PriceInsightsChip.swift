import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// Google Flights' own low / typical / high verdict for the searched dates. Nothing when the level is missing.
struct PriceInsightsChip: View {
    let insights: JSONValue

    private var family: Family {
        switch Commerce.insightLevel(insights) {
        case "low": .green
        case "high": .amber
        default: .gray
        }
    }

    static func text(_ insights: JSONValue) -> String? {
        guard let level = Commerce.insightLevel(insights) else { return nil }
        let key: LKey
        switch level {
        case "low": key = K.alerts.fare.level.low
        case "high": key = K.alerts.fare.level.high
        default: key = K.alerts.fare.level.typical
        }
        var text = L10n.text(key)
        if let range = Commerce.typicalRange(insights) {
            text += " · " + L10n.text(
                K.alerts.fare.typical,
                ["low": Fmt.currency(range.low, code: "USD"), "high": Fmt.currency(range.high, code: "USD")])
        }
        return text
    }

    var body: some View {
        if let text = Self.text(insights) {
            // The source name is a brand: never translated.
            (Text(verbatim: text) + Text(verbatim: " · Google Flights").foregroundStyle(SemanticColor.textMuted))
                .font(VFont.body(.caption, weight: .medium))
                .foregroundStyle(Palette.color(family, .s700))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Palette.color(family, .s100), in: Capsule())
                .overlay { Capsule().strokeBorder(Palette.color(family, .s200), lineWidth: 1) }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("results.flights.price-insights")
        }
    }
}
