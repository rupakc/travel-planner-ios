import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// Where the plan's money goes: a stacked bar plus one row per category, the total and the budget note.
struct CostBreakdownView: View {
    let parts: [CostPart]
    let total: Double
    let budget: BudgetNote?
    let showsTransportNote: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    static func label(for part: CostPart) -> String {
        switch part.key {
        case "flights": L10n.text(K.plan.cost.cat.flights)
        case "hotel": L10n.text(K.plan.cost.cat.hotel)
        case "activities": L10n.text(K.plan.cost.cat.activities)
        case "sim": L10n.text(K.plan.cost.cat.sim)
        default: part.label
        }
    }

    static func color(for key: String) -> Color {
        SectionAccent.color(for: key == "hotel" ? "hotels" : key)
    }

    /// Whole dollars, like the web's breakdown.
    static func usd0(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(LanguageController.current.intlLocale))
    }

    /// Item prices: no cents unless there are some.
    static func usdUpTo2(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(0...2)).locale(LanguageController.current.intlLocale))
    }

    static func percent(_ share: Double) -> String {
        share > 0 && share < 0.005 ? "<1%" : Fmt.number(share * 100, fractionDigits: 0) + "%"
    }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.plan.cost.heading))
                    .font(VFont.display(.headline))
                    .foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                bar
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        row(part, emphasised: index == 0)
                    }
                }
                Divider()
                totalRow
                if let budget { budgetChip(budget) }
                if showsTransportNote {
                    Text(verbatim: L10n.text(K.plan.cost.transportNote))
                        .font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.cost")
    }

    private var bar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(parts) { part in
                    Self.color(for: part.key)
                        .frame(width: max(2, proxy.size.width * (total > 0 ? part.amount / total : 0)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel(parts.map { "\(Self.label(for: $0)) \(Self.percent($0.amount / max(total, 1)))" }.joined(separator: ", "))
    }

    private func row(_ part: CostPart, emphasised: Bool) -> some View {
        let share = total > 0 ? part.amount / total : 0
        let title = Text(verbatim: Self.label(for: part))
            .font(VFont.body(.subheadline, weight: emphasised ? .semibold : .regular))
            .foregroundStyle(SemanticColor.text)
        let amount = Text(verbatim: Self.usd0(part.amount))
            .font(VFont.body(.subheadline, weight: .medium))
            .foregroundStyle(SemanticColor.text)
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Circle().fill(Self.color(for: part.key)).frame(width: 8, height: 8).accessibilityHidden(true)
            if typeSize.isAccessibilitySize {
                // Label above the amount: a long word never breaks letter by letter.
                VStack(alignment: .leading, spacing: 2) {
                    title
                    amount + Text(verbatim: "  " + Self.percent(share)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                }
            } else {
                title.frame(maxWidth: .infinity, alignment: .leading)
                amount.fixedSize()
                Text(verbatim: Self.percent(share))
                    .font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.textMuted)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var totalRow: some View {
        let label = Text(verbatim: L10n.text(K.plan.cost.total))
            .font(VFont.body(.subheadline, weight: .semibold))
            .foregroundStyle(SemanticColor.text)
        let value = Text(verbatim: Self.usd0(total)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { label; value }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    label.frame(maxWidth: .infinity, alignment: .leading)
                    value.fixedSize()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func budgetChip(_ budget: BudgetNote) -> some View {
        let family: Family = budget.isOver ? .red : .emerald
        return Text(verbatim: budget.label)
            .font(VFont.body(.footnote, weight: .medium))
            .foregroundStyle(Palette.color(family, .s700))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .borderedSurface(RoundedRectangle(cornerRadius: 14), fill: Palette.color(family, .s50), border: Palette.color(family, .s200))
            .accessibilityIdentifier("plan.cost.budget")
    }
}
