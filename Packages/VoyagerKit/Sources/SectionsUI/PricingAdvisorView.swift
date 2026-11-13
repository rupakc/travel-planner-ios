import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// The booking-timing advisor: a trend sparkline, the verdict, the recommendation, and the "historical pattern
/// estimate, not live market data" line the web always shows. Nothing without trend data.
public struct PricingAdvisorView: View {
    let data: JSONValue
    let ctx: SectionContext
    @State private var expanded = false

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    private var trend: [(days: Double, price: Double)] {
        (data["trend_data"].array ?? []).compactMap { point in
            guard let days = point["days_before"].double, let price = point["relative_price"].double,
                days.isFinite, price.isFinite
            else { return nil }
            return (days, price)
        }
    }

    private var statusFamily: Family {
        switch data["price_status"].string {
        case "above_average": .red
        case "below_average": .green
        default: .gray
        }
    }

    private var bookNow: Bool { data["recommendation"].string == "book_now" }

    public var body: some View {
        if !trend.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Sparkline(points: trend)
                        .frame(width: 96, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        if let label = data["price_status_label"].string ?? data["price_status"].string, !label.isEmpty {
                            CommerceTag(text: label, family: statusFamily)
                        }
                        CommerceTag(
                            text: bookNow ? L10n.text(K.results.pricing.bookNow) : L10n.text(K.results.pricing.considerWaiting),
                            family: bookNow ? .green : .amber)
                        if let level = data["confidence"].string, !level.isEmpty {
                            Text(verbatim: L10n.text(K.results.pricing.confidence, ["level": level.capitalized]))
                                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        }
                    }
                }
                if expanded {
                    if let detail = data["recommendation_detail"].string, !detail.isEmpty {
                        Text(verbatim: detail).font(VFont.body(.caption)).foregroundStyle(SemanticColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let window = data["optimal_booking_window"].string, !window.isEmpty {
                        Text(verbatim: L10n.text(K.results.pricing.bestWindow, ["window": window]))
                            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    expanded.toggle()
                } label: {
                    Text(verbatim: L10n.text(expanded ? K.results.toggle.less : K.results.toggle.why))
                        .font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("results.pricing.toggle")
                Text(verbatim: L10n.text(K.results.pricing.estimate, ["disclaimer": data["disclaimer"].string ?? ""]))
                    .font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.color(statusFamily, .s50), in: RoundedRectangle(cornerRadius: Radius.itemCard))
            .overlay { RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(Palette.color(statusFamily, .s200), lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("results.pricing")
        }
    }
}

/// Relative price against days before departure (far left, now on the right).
private struct Sparkline: View {
    let points: [(days: Double, price: Double)]

    var body: some View {
        SparklineShape(points: points)
            .stroke(SemanticColor.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

private struct SparklineShape: Shape {
    let points: [(days: Double, price: Double)]

    func path(in rect: CGRect) -> Path {
        let maxDays = max(points.map(\.days).max() ?? 1, 1)
        let prices = points.map(\.price)
        let low = prices.min() ?? 0
        let span = max((prices.max() ?? 1) - low, 0.0001)
        var path = Path()
        for (index, point) in points.sorted(by: { $0.days > $1.days }).enumerated() {
            let location = CGPoint(
                x: rect.minX + rect.width * (1 - point.days / maxDays),
                y: rect.minY + rect.height * ((1 - (point.price - low) / span) * 0.9 + 0.05))
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        return path
    }
}
