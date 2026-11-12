import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// Compare mode: shared trip fields, two or three destinations, then a side-by-side table.
public struct CompareView: View {
    @State private var model: CompareModel

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: CompareModel(env: env))
    }

    @MainActor init(model: CompareModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                form
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                if !model.columns.isEmpty {
                    // VStack, not LazyVStack: three columns only, and lazy stacks hang hosted snapshot tests.
                    CompareTable(
                        columns: model.columns, best: model.best,
                        onPlan: { model.plan($0) },
                        onRetry: { index in Task { await model.retry(index) } })
                }
            }
            .padding(Spacing.lg)
        }
        .task { await model.prefillFromPreferences() }
        .accessibilityIdentifier("compare.root")
    }

    private var form: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.search.compare.intro))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
                field(K.search.form.flyingFrom, K.search.form.cityOrAirport, text: $model.origin, id: "compare.origin")
                ForEach(model.destinations.indices, id: \.self) { index in
                    destinationRow(index)
                }
                if model.canAddDestination {
                    VButton(L10n.text(K.search.compare.addAnother), tid: "compare.add", role: .tonal, systemImage: "plus") {
                        model.addDestination()
                    }
                }
                DatePicker(L10n.text(K.search.form.departure), selection: $model.departure, displayedComponents: .date)
                    .accessibilityIdentifier("compare.departure")
                DatePicker(
                    L10n.text(K.search.form.return), selection: $model.returnDate, in: model.departure..., displayedComponents: .date
                )
                .accessibilityIdentifier("compare.return")
                field(
                    K.search.form.nationality, K.search.form.nationalityPlaceholder, text: $model.nationality,
                    id: "compare.nationality")
                field(
                    K.search.form.budgetOptional, K.search.form.totalBudget, text: $model.budget, id: "compare.budget",
                    numeric: true)
                Stepper(value: $model.adults, in: 1...9) {
                    Text(verbatim: "\(L10n.text(K.search.form.travelers)): \(model.adults)")
                }
                .accessibilityIdentifier("compare.travelers")
                WrapLayout(spacing: Spacing.sm) {
                    ForEach(CompareModel.interestIDs, id: \.self) { id in
                        VChip(title: Self.interestTitle(id), tid: "compare.interest.\(id)", selected: model.interests.contains(id)) {
                            model.toggle(id)
                        }
                    }
                }
                if model.needTwo {
                    Text(verbatim: L10n.text(K.search.compare.needTwo))
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.destructive)
                        .accessibilityIdentifier("compare.needTwo")
                }
                VButton(
                    L10n.text(model.isLoading ? K.search.compare.comparing : K.search.compare.submit),
                    tid: "compare.submit", systemImage: "square.split.2x1"
                ) {
                    Task { await model.compare() }
                }
                .disabled(model.isLoading)
            }
        }
    }

    private func destinationRow(_ index: Int) -> some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            field(
                K.search.compare.destination, K.search.form.cityOrAirport,
                text: Binding(
                    get: { model.destinations.indices.contains(index) ? model.destinations[index] : "" },
                    set: { if model.destinations.indices.contains(index) { model.destinations[index] = $0 } }),
                id: "compare.destination.\(index)", args: ["n": String(index + 1)])
            if model.canRemoveDestination {
                Button {
                    model.removeDestination(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(L10n.text(K.search.compare.removeDestinationN, ["n": String(index + 1)]))
                .accessibilityIdentifier("compare.remove.\(index)")
            }
        }
    }

    private func field(
        _ label: LKey, _ placeholder: LKey, text: Binding<String>, id: String, numeric: Bool = false,
        args: [String: String] = [:]
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(label, args))
                .font(VFont.body(.footnote, weight: .medium))
                .foregroundStyle(SemanticColor.textMuted)
            TextField(L10n.text(placeholder), text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(numeric ? .decimalPad : .default)
                .accessibilityIdentifier(id)
        }
    }

    static func interestTitle(_ id: String) -> String {
        switch id {
        case "food": L10n.text(K.search.interests.food)
        case "history": L10n.text(K.search.interests.history)
        case "adventure": L10n.text(K.search.interests.adventure)
        case "culture": L10n.text(K.search.interests.culture)
        case "nature": L10n.text(K.search.interests.nature)
        case "shopping": L10n.text(K.search.interests.shopping)
        case "nightlife": L10n.text(K.search.interests.nightlife)
        case "wellness": L10n.text(K.search.interests.wellness)
        case "art": L10n.text(K.search.interests.art)
        default: L10n.text(K.search.interests.family)
        }
    }
}

/// A plain wrapping layout, so it also works in hosted snapshots.
private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
