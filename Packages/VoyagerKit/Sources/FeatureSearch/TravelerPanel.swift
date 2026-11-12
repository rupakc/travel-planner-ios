import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// Adults, seniors, children and infants (at least one traveller, at most 20) and accessibility needs.
struct TravelerPanel: View {
    let model: SearchFormModel

    private static let ages: [TravellerGroup: String] = [
        .adults: "18–64", .seniors: "65+", .children: "5–17", .infants: "0–4",
    ]

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.search.travelers.total, count: model.totalTravellers))
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                    .accessibilityIdentifier("search.travelers.total")
                ForEach(TravellerGroup.allCases, id: \.self) { group in row(group) }
                Divider()
                Text(verbatim: L10n.text(K.search.travelers.accessibility))
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(SearchFormModel.accessibilityIDs, id: \.self) { id in
                        VChip(
                            title: Self.accessLabel(id), tid: "search.access.\(id)",
                            selected: model.accessibility.contains(id)
                        ) { model.toggleAccessibility(id) }
                    }
                }
            }
        }
    }

    private func row(_ group: TravellerGroup) -> some View {
        let name = Self.groupName(group)
        return HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(VFont.body(.body))
                    .foregroundStyle(SemanticColor.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let age = Self.ages[group] {
                    Text(verbatim: age)
                        .font(VFont.body(.footnote))
                        .foregroundStyle(SemanticColor.textMuted)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: Spacing.sm)
            stepButton("minus.circle", group: group, delta: -1, label: K.search.travelers.fewer)
            Text(verbatim: "\(model.count(group))")
                .font(VFont.body(.body, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
                .frame(minWidth: 28)
                .accessibilityIdentifier("search.travelers.\(group.rawValue).count")
            stepButton("plus.circle", group: group, delta: 1, label: K.search.travelers.more)
        }
    }

    private func stepButton(_ icon: String, group: TravellerGroup, delta: Int, label: LKey) -> some View {
        Button { model.change(group, by: delta) } label: {
            Image(systemName: icon).font(.title2).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.canChange(group, by: delta) ? SemanticColor.primary : SemanticColor.textMuted)
        .disabled(!model.canChange(group, by: delta))
        .accessibilityLabel(L10n.text(label, ["group": Self.groupName(group)]))
        .accessibilityIdentifier("search.travelers.\(group.rawValue).\(delta < 0 ? "less" : "more")")
    }

    static func groupName(_ group: TravellerGroup) -> String {
        switch group {
        case .adults: L10n.text(K.search.travelers.adults)
        case .seniors: L10n.text(K.search.travelers.seniors)
        case .children: L10n.text(K.search.travelers.children)
        case .infants: L10n.text(K.search.travelers.infants)
        }
    }

    static func accessLabel(_ id: String) -> String {
        switch id {
        case "wheelchair": L10n.text(K.search.travelers.access.wheelchair)
        case "visual_impairment": L10n.text(K.search.travelers.access.visual_impairment)
        case "hearing_impairment": L10n.text(K.search.travelers.access.hearing_impairment)
        default: L10n.text(K.search.travelers.access.cognitive_disability)
        }
    }
}
