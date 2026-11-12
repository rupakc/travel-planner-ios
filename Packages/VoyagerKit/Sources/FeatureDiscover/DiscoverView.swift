import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// "Surprise me": a short form, then five destination cards with "Plan this trip".
public struct DiscoverView: View {
    @State private var model: DiscoverModel

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: DiscoverModel(env: env))
    }

    @MainActor init(model: DiscoverModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                form
                results
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .task { await model.prefillFromPreferences() }
        .accessibilityIdentifier("discover.root")
    }

    private var form: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                field(K.search.form.flyingFrom, K.search.form.cityOrAirport, text: $model.origin, id: "discover.origin")
                DatePicker(L10n.text(K.search.form.departure), selection: $model.departure, displayedComponents: .date)
                    .accessibilityIdentifier("discover.departure")
                DatePicker(
                    L10n.text(K.search.form.return), selection: $model.returnDate, in: model.departure..., displayedComponents: .date
                )
                .accessibilityIdentifier("discover.return")
                field(
                    K.search.form.nationality, K.search.form.nationalityPlaceholder, text: $model.nationality,
                    id: "discover.nationality")
                field(
                    K.search.form.budgetOptional, K.search.form.totalBudget, text: $model.budget, id: "discover.budget",
                    numeric: true)
                Stepper(value: $model.adults, in: 1...9) {
                    Text(verbatim: "\(L10n.text(K.search.form.travelers)): \(model.adults)")
                }
                .accessibilityIdentifier("discover.travelers")
                Text(verbatim: L10n.text(K.search.form.interestsDiscover))
                    .font(VFont.body(.subheadline, weight: .medium))
                    .foregroundStyle(SemanticColor.text)
                chips
                VButton(
                    L10n.text(model.isBusy ? K.search.discover.finding : K.search.discover.find),
                    tid: "discover.find", systemImage: "dice"
                ) {
                    Task { await model.find() }
                }
                .disabled(!model.canSubmit)
            }
        }
    }

    private func field(_ label: LKey, _ placeholder: LKey, text: Binding<String>, id: String, numeric: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(label))
                .font(VFont.body(.footnote, weight: .medium))
                .foregroundStyle(SemanticColor.textMuted)
            TextField(L10n.text(placeholder), text: text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(numeric ? .decimalPad : .default)
                .accessibilityIdentifier(id)
        }
    }

    private var chips: some View {
        FlowChips(items: DiscoverModel.interestIDs) { id in
            VChip(title: Self.interestTitle(id), tid: "discover.interest.\(id)", selected: model.interests.contains(id)) {
                model.toggle(id)
            }
        }
    }

    @ViewBuilder private var results: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            Skeleton(lines: 5)
        case .failed(let message):
            Text(verbatim: message)
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.destructive)
                .accessibilityIdentifier("discover.error")
        case .loaded(let list):
            if list.isEmpty {
                Text(verbatim: L10n.text(K.search.discover.none))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
            } else {
                // VStack, not LazyVStack: five cards only, and lazy stacks hang hosted snapshot tests.
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(verbatim: L10n.text(K.search.discover.picks))
                        .font(VFont.display(.title3))
                        .foregroundStyle(SemanticColor.text)
                    ForEach(Array(list.prefix(5).enumerated()), id: \.offset) { index, item in
                        DestinationCard(suggestion: item, index: index) { model.planThis(item) }
                    }
                }
            }
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

/// Wrapping row of chips (a plain wrapping layout, so it also works in hosted snapshots).
private struct FlowChips<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        WrapLayout(spacing: Spacing.sm) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

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
