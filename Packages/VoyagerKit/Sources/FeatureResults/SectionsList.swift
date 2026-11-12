import DesignSystem
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerModel

/// The section-rendering seam: one `SectionCard` whose body is the registry's view for the section's data.
/// Every host of result sections (this screen's list and detail column) goes through it.
struct ResultsSectionCard: View {
    let id: SectionID
    let entry: SectionEntry
    let ctx: SectionContext
    @Binding var expanded: Bool

    var body: some View {
        SectionCard(id: id, status: entry.status, verification: verification, expanded: $expanded) {
            if let data = entry.data { SectionRegistry.view(for: id, data: data, ctx: ctx) }
        }
    }

    private var verification: JSONValue? {
        guard ctx.showsVerification, let value = entry.data?["verification"], !value.isNull else { return nil }
        return value
    }
}

extension ResultsState {
    /// Sections to show, in the web's order: still loading, failed, or holding data. A finished section with
    /// nothing to show (a packing list that never came) is left out.
    var visibleSections: [SectionID] {
        SectionID.allCases.filter { id in
            guard let entry = sections[id] else { return false }
            switch entry.status {
            case .waiting: return false
            case .loading, .error: return true
            case .done, .enhancing: return entry.data != nil
            }
        }
    }
}

/// iPhone: the section cards, one under the other. `lazy: false` is for snapshot hosting, where a lazy stack hangs.
struct SectionsList: View {
    let state: ResultsState
    let ctx: SectionContext
    let lazy: Bool
    @Binding var collapsed: Set<SectionID>

    var body: some View {
        if lazy {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) { cards }
        } else {
            VStack(alignment: .leading, spacing: Spacing.lg) { cards }
        }
    }

    private var cards: some View {
        ForEach(state.visibleSections) { id in
            ResultsSectionCard(id: id, entry: state.sections[id] ?? SectionEntry(status: .loading), ctx: ctx, expanded: expanded(id))
        }
    }

    private func expanded(_ id: SectionID) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id) },
            set: { open in
                if open { collapsed.remove(id) } else { collapsed.insert(id) }
            })
    }
}

/// iPad content column: one row per section (icon, title, status); selecting a row shows it in the detail column.
struct SectionIndexList: View {
    let state: ResultsState
    @Binding var selected: SectionID?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(state.visibleSections) { id in
                Button {
                    selected = id
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: id.indexSymbol)
                            .foregroundStyle(SectionAccent.color(for: id.rawValue))
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(verbatim: id.title)
                            .font(VFont.body(.body, weight: selected == id ? .semibold : .regular))
                            .foregroundStyle(SemanticColor.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Spacing.xs)
                        statusIcon(state.status(id))
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 44)
                    .background(
                        selected == id ? Palette.color(.teal, .s100) : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.input))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("results.index.\(id.rawValue)")
                .accessibilityAddTraits(selected == id ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func statusIcon(_ status: SectionStatus) -> some View {
        switch status {
        case .loading: ProgressView().controlSize(.small)
        case .enhancing: Image(systemName: "sparkles").foregroundStyle(Palette.color(.amber, .s700)).accessibilityHidden(true)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.color(.teal, .s600).opacity(0.7)).accessibilityHidden(true)
        case .error: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SemanticColor.destructive).accessibilityHidden(true)
        case .waiting: EmptyView()
        }
    }
}

extension SectionID {
    /// The row icon; `SectionID.symbol` is module-internal to SectionsUI.
    var indexSymbol: String {
        switch self {
        case .flights: "airplane"
        case .weather: "cloud.sun"
        case .hotels: "bed.double"
        case .activities: "figure.hiking"
        case .placesToSee: "mappin.and.ellipse"
        case .walkingTours: "figure.walk"
        case .events: "ticket"
        case .visa: "doc.text"
        case .sim: "simcard"
        case .tips: "lightbulb"
        case .emergencyCard: "cross.case"
        case .gettingAround: "tram"
        case .forex: "dollarsign.circle"
        case .itinerary: "calendar"
        case .stressTest: "checkmark.shield"
        case .packingList: "suitcase"
        }
    }
}
