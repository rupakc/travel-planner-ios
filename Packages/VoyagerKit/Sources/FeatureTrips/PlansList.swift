import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// The saved plans: search by name, filter by upcoming or past, tap to open, context menu to delete.
/// Stacks rather than a lazy list so it also renders in hosted snapshots (a user has few plans).
struct PlansList: View {
    @Bindable var model: TripsModel
    let selectedID: Int?
    let onSelect: (Int) -> Void
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            searchField
            filters
            let plans = model.visiblePlans
            if plans.isEmpty {
                Text(verbatim: L10n.text(K.mobile.trips.noMatch))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(plans, id: \.id) { plan in row(plan) }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SemanticColor.textMuted)
                .accessibilityHidden(true)
            TextField(L10n.text(K.mobile.trips.searchPlans), text: $model.query)
                .font(VFont.body(.body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("trips.search")
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 44)
        .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.input))
        .overlay { RoundedRectangle(cornerRadius: Radius.input).strokeBorder(SemanticColor.border) }
    }

    private var filters: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(PlanFilter.allCases, id: \.self) { filter in
                VChip(title: Self.title(filter), tid: "trips.filter.\(filter.rawValue)", selected: model.filter == filter) {
                    model.filter = filter
                }
            }
        }
    }

    static func title(_ filter: PlanFilter) -> String {
        switch filter {
        case .all: L10n.text(K.mobile.trips.filterAll)
        case .upcoming: L10n.text(K.mobile.trips.filterUpcoming)
        case .past: L10n.text(K.mobile.trips.filterPast)
        }
    }

    private func row(_ plan: PlanSummary) -> some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: "trips.plan", route: route))
            onSelect(plan.id)
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: plan.name ?? plan.searchData["destination"].string ?? "")
                        .font(VFont.body(.body, weight: .medium))
                        .foregroundStyle(SemanticColor.text)
                        .multilineTextAlignment(.leading)
                    if let line = PlanDetailView.tripLine(plan.searchData) {
                        Text(verbatim: line)
                            .font(VFont.body(.footnote))
                            .foregroundStyle(SemanticColor.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(SemanticColor.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                selectedID == plan.id ? SemanticColor.primary.opacity(0.12) : SemanticColor.surfaceRaised,
                in: RoundedRectangle(cornerRadius: Radius.itemCard))
            .overlay { RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border) }
            .contentShape(RoundedRectangle(cornerRadius: Radius.itemCard))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trips.plan.\(plan.id)")
        .contextMenu {
            Button(L10n.text(K.plan.modal.delete), role: .destructive) { model.requestDelete(plan) }
        }
        .accessibilityAction(named: L10n.text(K.plan.modal.delete)) { model.requestDelete(plan) }
    }
}
