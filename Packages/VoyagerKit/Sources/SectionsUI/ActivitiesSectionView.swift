import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Activities: items from the user's link first (badged), then the rest in the backend's relevance order; filters.
public struct ActivitiesSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    @State private var filter = FilteredSection()

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let items = Commerce.activitiesFromLinkFirst((filter.override ?? data)["results"].array ?? [])
        VStack(alignment: .leading, spacing: Spacing.md) {
            if ctx.filtered != nil {
                FilterBar(
                    activeCount: filter.override == nil ? 0 : filter.draft.activeCount(for: .activities), tidPrefix: "results.activities",
                    onOpen: { filter.sheet = true }, onClear: clear, clearTitle: L10n.text(K.sections.page.clearActivityFilters))
            }
            if let failure = filter.failure {
                Text(verbatim: failure).font(VFont.body(.caption)).foregroundStyle(SemanticColor.destructive)
            }
            if items.isEmpty {
                CommerceEmpty(text: L10n.text(K.results.activities.none))
            } else {
                CommerceRows(count: items.count, layout: ctx.layout) { index in
                    ActivityRow(activity: items[index], ctx: ctx)
                }
            }
        }
        .onChange(of: data) { _, _ in filter.override = nil }
        .sheet(isPresented: $filter.sheet) {
            FilterSheet(section: .activities, draft: $filter.draft, busy: filter.busy, onApply: apply, onClear: clear)
        }
    }

    private func apply() {
        guard let run = ctx.filtered else { return }
        let filters = filter.draft.serverFilters(for: .activities)
        filter.busy = true
        Task {
            let result = await run(.activities, filters)
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
