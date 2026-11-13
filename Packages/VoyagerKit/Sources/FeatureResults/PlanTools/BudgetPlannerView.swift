import DesignSystem
import Domain
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerModel

/// Splits the per-person budget into flights / stay / activities and shows what of the loaded results fits.
struct BudgetPlannerView: View {
    let allocation: BudgetPlanner.Allocation
    let fit: BudgetPlanner.FitResult
    let cheaper: CheaperHotels?
    let ctx: SectionContext
    let onChange: (String, Double) -> Void
    let onTotal: (Double) -> Void
    let onReset: () -> Void
    let onFindCheaper: (Double) -> Void

    @State private var open = true
    @State private var draftTotal: String?

    private static let categories = BudgetPlanner.keys

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Button { open.toggle() } label: {
                    HStack(spacing: Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text(verbatim: L10n.text(K.plan.budget.title)).font(VFont.body(.headline, weight: .semibold))
                            } icon: {
                                Image(systemName: "wallet.pass").foregroundStyle(SemanticColor.primary)
                            }
                            Text(verbatim: L10n.text(K.plan.budget.subtitle))
                                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        }
                        Spacer(minLength: Spacing.sm)
                        Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(SemanticColor.textMuted)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(open ? "expanded" : "collapsed")
                .accessibilityIdentifier("plan.budget-toggle")
                if open { editor }
            }
        }
        .accessibilityIdentifier("results.budgetPlanner")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            totalRow
            ForEach(Self.categories, id: \.self) { key in category(key) }
            HStack {
                Text(verbatim: L10n.text(K.plan.budget.else)).font(VFont.body(.caption, weight: .semibold))
                Text(verbatim: L10n.text(K.plan.budget.elseHint)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                Spacer(minLength: Spacing.sm)
                Text(verbatim: PlanToolsFormat.usd(allocation.other)).font(VFont.body(.subheadline, weight: .bold))
            }
            .accessibilityElement(children: .combine)
            cheaperResults
        }
    }

    private var totalRow: some View {
        HStack(spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.plan.budget.total)).font(VFont.body(.caption, weight: .semibold))
            TextField("", text: totalBinding)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .font(VFont.body(.subheadline, weight: .semibold))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
                .onSubmit(commitTotal)
                .accessibilityLabel(L10n.text(K.plan.budget.total))
                .accessibilityIdentifier("plan.budget-total")
            Text(verbatim: L10n.text(K.plan.budget.perPerson)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            Spacer(minLength: 0)
            Button(L10n.text(K.plan.budget.reset), action: onReset)
                .font(VFont.body(.caption, weight: .semibold))
                .frame(minHeight: 44)
                .accessibilityIdentifier("plan.budget-reset")
        }
    }

    private var totalBinding: Binding<String> {
        Binding(
            get: { draftTotal ?? (allocation.sum.isFinite ? String(format: "%.0f", allocation.sum) : "0") },
            set: { draftTotal = $0 })
    }

    private func commitTotal() {
        defer { draftTotal = nil }
        guard let text = draftTotal, let value = Double(text.trimmingCharacters(in: .whitespaces)),
            value.isFinite, value > 0 else { return }
        onTotal(value.rounded())
    }

    private func name(_ key: String) -> String {
        switch key {
        case "flights": L10n.text(K.plan.budget.cat.flights)
        case "stay": L10n.text(K.plan.budget.cat.stay)
        default: L10n.text(K.plan.budget.cat.activities)
        }
    }

    private func noun(_ key: String) -> String {
        switch key {
        case "flights": L10n.text(K.plan.budget.noun.flights)
        case "stay": L10n.text(K.plan.budget.noun.stay)
        default: L10n.text(K.plan.budget.noun.activities)
        }
    }

    private func fitText(_ key: String) -> String {
        switch key {
        case "flights":
            return L10n.text(K.plan.budget.fit.flights, ["fits": "\(fit.flights.count)"], count: fit.flights.total)
        case "stay":
            return L10n.text(K.plan.budget.fit.hotels, ["fits": "\(fit.hotels.count)"], count: fit.hotels.total)
        default:
            return L10n.text(K.plan.budget.fit.activities, ["spent": PlanToolsFormat.usd(fit.spent)], count: fit.picked.count)
        }
    }

    private func category(_ key: String) -> some View {
        let upper = max(allocation.sum, 10)
        let binding = Binding<Double>(
            get: { min(max(allocation[key], 0), upper) },
            set: { onChange(key, $0) })
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: name(key)).font(VFont.body(.caption, weight: .semibold))
                Spacer(minLength: Spacing.sm)
                Text(verbatim: PlanToolsFormat.usd(allocation[key])).font(VFont.body(.subheadline, weight: .bold))
            }
            .accessibilityHidden(true)
            Slider(value: binding, in: 0...upper, step: 10)
                .tint(SemanticColor.primary)
                .accessibilityLabel(name(key))
                .accessibilityValue(L10n.text(K.plan.budget.valueText, ["amount": PlanToolsFormat.usd(allocation[key]), "noun": noun(key)]))
                .accessibilityIdentifier("plan.budget-slider-\(key)")
            Text(verbatim: fitText(key)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            if key == "stay", let maxNightly = PlanToolsModel.maxNightly(allocation, fit) {
                VButton(
                    cheaper == .loading ? L10n.text(K.plan.budget.findingCheaper) : L10n.text(K.plan.budget.cheaper),
                    tid: "plan.budget-cheaper-hotels", role: .tonal) { onFindCheaper(maxNightly) }
                    .disabled(cheaper == .loading)
            }
        }
    }

    @ViewBuilder private var cheaperResults: some View {
        switch cheaper {
        case .failed(let message):
            Text(verbatim: message).font(VFont.body(.caption)).foregroundStyle(SemanticColor.destructive)
        case .loaded(_, let hotels):
            if hotels.isEmpty {
                Text(verbatim: L10n.text(K.sections.page.noResults)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            } else {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(hotels.prefix(3).enumerated()), id: \.offset) { _, hotel in cheaperRow(hotel) }
                }
            }
        case .loading, nil:
            EmptyView()
        }
    }

    private func cheaperRow(_ hotel: JSONValue) -> some View {
        let selected = ctx.isSelected("hotel", hotel)
        let nightly = PlanToolsFormat.amount(hotel["price_per_night_usd"])
        return HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: hotel["name"].string ?? "").font(VFont.body(.subheadline, weight: .semibold))
                if let nightly {
                    Text(verbatim: L10n.text(K.plan.best.perNight, ["price": PlanToolsFormat.usd(nightly)]))
                        .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                }
            }
            Spacer(minLength: Spacing.sm)
            Button { ctx.toggle("hotel", hotel) } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(hotel["name"].string ?? "")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
