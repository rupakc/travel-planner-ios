import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// What's on (api-contract 3.4.7): dates (with the "typical season" caveat), location, price, impact.
public struct EventsSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let events = Info.list(data, "results")
        if events.isEmpty {
            InfoEmpty(key: K.results.events.none)
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(Array(events.enumerated()), id: \.offset) { _, event in card(event) }
            }
        }
    }

    private func card(_ event: JSONValue) -> some View {
        let start = Info.shortDate(Info.text(event["start_date"]))
        let end = Info.shortDate(Info.text(event["end_date"]))
        let dates = [start, end].compactMap { $0 }
        let range = dates.count == 2 && dates[0] != dates[1] ? dates.joined(separator: " – ") : dates.first
        return VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: SectionItem(event).name ?? "")
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.sm) {
                    if let category = Info.text(event["category"]) { InfoTag(title: category, family: .violet) }
                    if event["impact"].string == "highlight" { InfoTag(title: "★", family: .amber) }
                }
                InfoLine(label: nil, value: range)
                if event["date_certainty"].string == "typical_season" {
                    Text(verbatim: L10n.text(K.results.events.typicalSeason))
                        .font(VFont.body(.caption))
                        .foregroundStyle(Palette.color(.amber, .s700))
                        .fixedSize(horizontal: false, vertical: true)
                }
                InfoLine(label: nil, value: Info.text(event["location"]))
                InfoLine(label: nil, value: Info.text(event["description"]))
                InfoLine(label: nil, value: Info.text(event["price"]))
                HStack {
                    Spacer(minLength: 0)
                    PlanToggle(field: "events", item: event, ctx: ctx)
                }
            }
        }
    }
}
