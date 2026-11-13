import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Hotels grouped by budget tier (luxury first), with filters. Prices are the hotel agent's, labelled when estimated.
public struct HotelsSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    @State private var filter = FilteredSection()

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    static func tierTitle(_ tier: HotelTier) -> String {
        switch tier {
        case .luxury: L10n.text(K.sections.commerce.tier.luxury)
        case .premium: L10n.text(K.sections.commerce.tier.premium)
        case .midRange: L10n.text(K.sections.commerce.tier.midRange)
        case .budget: L10n.text(K.sections.commerce.tier.budget)
        case .other: L10n.text(K.sections.commerce.tier.other)
        }
    }

    /// The hotels shown: the server's, then the on-device minimum stars.
    private var hotels: [JSONValue] {
        let all = (filter.override ?? data)["results"].array ?? []
        guard let minimum = filter.draft.minStars else { return all }
        return all.filter { ($0["star_rating"].double ?? 0) >= Double(minimum) }
    }

    public var body: some View {
        let tiers = Commerce.hotelTiers(hotels)
        VStack(alignment: .leading, spacing: Spacing.md) {
            if ctx.filtered != nil {
                FilterBar(
                    activeCount: filter.draft.activeCount(for: .hotels), tidPrefix: "results.hotels",
                    onOpen: { filter.sheet = true }, onClear: clear, clearTitle: L10n.text(K.sections.page.clearHotelFilters))
            }
            if let failure = filter.failure {
                Text(verbatim: failure).font(VFont.body(.caption)).foregroundStyle(SemanticColor.destructive)
            }
            if tiers.isEmpty {
                CommerceEmpty(text: L10n.text(K.results.hotels.none))
            } else {
                ForEach(tiers, id: \.tier) { group in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(verbatim: Self.tierTitle(group.tier))
                            .font(VFont.body(.subheadline, weight: .semibold))
                            .foregroundStyle(SemanticColor.text)
                            .accessibilityAddTraits(.isHeader)
                        CommerceRows(count: group.hotels.count, layout: ctx.layout) { index in
                            HotelRow(hotel: group.hotels[index], ctx: ctx)
                        }
                    }
                }
            }
        }
        .onChange(of: data) { _, _ in filter.override = nil }
        .sheet(isPresented: $filter.sheet) {
            FilterSheet(section: .hotels, draft: $filter.draft, busy: filter.busy, onApply: apply, onClear: clear)
        }
    }

    private func apply() {
        guard let run = ctx.filtered else { return }
        let filters = filter.draft.serverFilters(for: .hotels)
        guard !(filters.object ?? [:]).isEmpty else {
            filter.override = nil
            filter.failure = nil
            return
        }
        filter.busy = true
        Task {
            let result = await run(.hotels, filters)
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
