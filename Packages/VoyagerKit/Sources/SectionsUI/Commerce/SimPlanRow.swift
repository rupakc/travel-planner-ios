import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// One SIM or eSIM plan: provider, data, validity, price (static plans are labelled estimates), Add to plan / Get plan.
/// A SIM plan is a single choice: picking another replaces it. There is nothing live to watch.
struct SimPlanRow: View {
    let plan: JSONValue
    let ctx: SectionContext

    private var item: SectionItem { SectionItem(plan) }

    static func dataText(_ plan: JSONValue) -> String? {
        let data = Commerce.simData(plan)
        if data.unlimited { return L10n.text(K.results.sim.unlimited) }
        return data.gb.map { L10n.text(K.results.sim.dataGb, ["gb": $0]) }
    }

    static func validityText(_ plan: JSONValue) -> String? {
        guard let days = plan["validity_days"].int, days > 0 else { return nil }
        return L10n.text(K.results.sim.validity, count: days)
    }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: plan["provider"].string ?? item.name ?? "")
                            .font(VFont.body(.subheadline, weight: .semibold))
                            .foregroundStyle(SemanticColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let planName = plan["plan_name"].string, !planName.isEmpty {
                            Text(verbatim: planName).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        }
                    }
                    Spacer(minLength: Spacing.sm)
                    PriceText(amount: item.priceUSD, currency: "USD", estimate: plan["source"].string == "estimate")
                }
                Text(verbatim: [Self.dataText(plan), Self.validityText(plan)].compactMap { $0 }.joined(separator: " · "))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                if let coverage = plan["network_quality"]["coverage_description"].string, !coverage.isEmpty {
                    Text(verbatim: coverage).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RowActions(
                    tidPrefix: "results.sim", selected: ctx.isSelected("sim", plan),
                    toggle: { ctx.toggle("sim", plan) }, bookURL: item.bookingURL, section: "sim")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
