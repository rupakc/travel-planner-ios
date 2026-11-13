import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Day-by-day forecast (api-contract 3.4.2): description, high/low, precipitation and wind, with poor days flagged.
public struct WeatherSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let days = Info.list(data, "days")
        if days.isEmpty {
            InfoEmpty(key: K.sections.page.noResults)
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if data["source"].string == "llm-estimate" {
                    InfoTag(title: L10n.text(K.results.weather.estimate), family: .amber)
                }
                let poor = Int(data["poor_weather_day_count"].double ?? 0)
                if poor > 0 {
                    Text(verbatim: L10n.text(K.results.weather.poorDays, count: poor))
                        .font(VFont.body(.footnote, weight: .medium))
                        .foregroundStyle(Palette.color(.amber, .s700))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in row(day) }
            }
        }
    }

    private func row(_ day: JSONValue) -> some View {
        let poor = day["is_poor"].bool == true
        return HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: WeatherSymbol.name(code: day["weather_code"].int))
                .font(.title3)
                .foregroundStyle(poor ? Palette.color(.amber, .s600) : SectionAccent.color(for: "weather"))
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: [Info.shortDate(Info.text(day["date"])), Info.text(day["city"])].compactMap { $0 }.joined(separator: " · "))
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                InfoLine(label: nil, value: Info.text(day["description"]))
                HStack(spacing: Spacing.md) {
                    if let high = day["temp_high_c"].double, let low = day["temp_low_c"].double {
                        Text(verbatim: "\(Int(high.rounded()))° / \(Int(low.rounded()))°")
                    }
                    if let mm = day["precipitation_mm"].double, mm > 0 {
                        Text(verbatim: L10n.text(K.results.weather.precip, ["mm": Fmt.number(mm, fractionDigits: 1)]))
                    }
                }
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
