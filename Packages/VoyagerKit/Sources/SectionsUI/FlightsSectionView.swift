import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Flights: the Google Flights verdict chip, filters, the opt-in fare calendar, and the fares (one group per leg on
/// a multi-city trip). Estimates are labelled and cannot be watched.
public struct FlightsSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    @State private var filter = FilteredSection()
    @State private var calendarOpen = false
    @State private var calendarUnavailable = false

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    private var current: JSONValue { filter.override ?? data }

    public var body: some View {
        let groups = Commerce.flightGroups(current)
        let multi = Commerce.isMultiCity(current)
        VStack(alignment: .leading, spacing: Spacing.md) {
            if current["price_insights"].object != nil { PriceInsightsChip(insights: current["price_insights"]) }
            controls
            if calendarOpen, !calendarUnavailable, let load = ctx.fareCalendar {
                FareCalendarStrip(load: load, onUnavailable: { calendarUnavailable = true })
            }
            if let failure = filter.failure {
                Text(verbatim: failure).font(VFont.body(.caption)).foregroundStyle(SemanticColor.destructive)
            }
            if multi {
                let progress = Commerce.legProgress(current) { ctx.isSelected("flights", $0) }
                Text(verbatim: L10n.text(K.results.flights.multiCity, ["chosen": String(progress.chosen), "total": String(progress.total)]))
                    .font(VFont.body(.caption, weight: .medium))
                    .foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if groups.allSatisfy({ $0.flights.isEmpty && $0.error == nil }) && !multi {
                CommerceEmpty(text: L10n.text(K.results.flights.none))
            } else {
                ForEach(groups) { group in groupView(group, multi: multi) }
            }
        }
        .onChange(of: data) { _, _ in filter.override = nil }
        .sheet(isPresented: $filter.sheet) {
            FilterSheet(section: .flights, draft: $filter.draft, busy: filter.busy, onApply: apply, onClear: clear)
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { controlButtons }
            VStack(alignment: .leading, spacing: Spacing.sm) { controlButtons }
        }
    }

    @ViewBuilder private var controlButtons: some View {
        if ctx.filtered != nil {
            FilterBar(
                activeCount: filter.override == nil ? 0 : filter.draft.activeCount(for: .flights), tidPrefix: "results.flights",
                onOpen: { filter.sheet = true }, onClear: clear, clearTitle: L10n.text(K.sections.page.clearFlightFilters))
        }
        if ctx.fareCalendar != nil, !calendarUnavailable, !Commerce.isMultiCity(current) {
            VButton(
                L10n.text(K.sections.page.fareCalendar), tid: "page.fare-calendar", role: calendarOpen ? .primary : .tonal,
                systemImage: "calendar"
            ) {
                calendarOpen.toggle()
            }
            .accessibilityAddTraits(calendarOpen ? .isSelected : [])
        }
    }

    @ViewBuilder private func groupView(_ group: FlightLegGroup, multi: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if multi {
                let leg = L10n.text(K.results.flights.leg, ["n": String(group.id + 1)])
                Text(verbatim: [leg, group.label].compactMap { $0 }.joined(separator: " · "))
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if group.flights.isEmpty {
                if multi { CommerceEmpty(text: group.error ?? L10n.text(K.results.flights.noLegFlights)) }
            } else {
                CommerceRows(count: group.flights.count, layout: ctx.layout) { index in
                    FlightRow(flight: group.flights[index], ctx: ctx)
                }
            }
        }
    }

    private func apply() {
        guard let run = ctx.filtered else { return }
        let filters = filter.draft.serverFilters(for: .flights)
        filter.busy = true
        Task {
            let result = await run(.flights, filters)
            filter.busy = false
            if case .loaded(let value) = result {
                filter.override = value
                filter.failure = nil
            } else {
                filter.failure = L10n.text(K.sections.page.filterError)
            }
        }
    }

    private func clear() {
        filter.draft = FilterDraft()
        filter.override = nil
        filter.failure = nil
    }
}
