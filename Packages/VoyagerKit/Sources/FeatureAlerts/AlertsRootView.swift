import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// The Alerts tab: watched flights, hotels, activities and trips with a kind filter, per-watch actions, the live
/// web search sheet and a bell into the notification inbox. `kind` / `watchID` open the given watch.
public struct AlertsRootView: View {
    @State private var model: AlertsModel
    @State private var deleting: WatchRow?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @MainActor public init(env: AppEnvironment, kind: WatchKind?, watchID: Int?) {
        _model = State(initialValue: AlertsModel(env: env, kind: kind, watchID: watchID))
    }

    @MainActor init(model: AlertsModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // The system caps the bar title small; at accessibility sizes the heading is repeated here so it
                    // follows Dynamic Type and wraps by word.
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(verbatim: L10n.text(K.alerts.page.title))
                            .font(VFont.display(.title))
                            .foregroundStyle(SemanticColor.text)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: L10n.text(K.alerts.page.intro))
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    content
                }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(Spacing.lg)
            }
            .refreshable { await model.load() }
            .onChange(of: model.focusedID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .navigationTitle(L10n.text(K.alerts.page.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !model.notifications404 {
                ToolbarItem(placement: .primaryAction) { bell }
            }
        }
        .task {
            await model.load()
            await model.loadInbox()
        }
        .sheet(item: $model.editing) { row in
            WatchEditor(
                row: row, hasEmail: model.hasEmail, saving: model.busy[row.id] == .save,
                onSave: { edit in Task { await model.save(row, edit) } },
                onCancel: { model.editing = nil })
        }
        .sheet(
            isPresented: Binding(get: { model.liveCheck != nil }, set: { if !$0 { model.dismissLiveCheck() } })
        ) {
            if let state = model.liveCheck { LiveCheckSheet(state: state, onDismiss: { model.dismissLiveCheck() }) }
        }
        .confirmationDialog(
            L10n.text(K.alerts.card.stopWatching), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.text(K.alerts.ui.delete), role: .destructive) {
                if let row = deleting { Task { await model.delete(row) } }
                deleting = nil
            }
            Button(L10n.text(K.alerts.ui.keep), role: .cancel) { deleting = nil }
        }
        .toast($model.toast)
        .accessibilityIdentifier("alerts.root")
    }

    private var bell: some View {
        Button {
            model.openInbox()
        } label: {
            Image(systemName: model.unread > 0 ? "bell.badge" : "bell")
        }
        .accessibilityLabel(
            model.unread > 0
                ? L10n.text(K.alerts.bell.notificationsUnread, ["n": String(model.unread)])
                : L10n.text(K.alerts.bell.notifications)
        )
        .accessibilityIdentifier("alerts.bell")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: Spacing.md) {
                ProgressView()
                Text(verbatim: L10n.text(K.alerts.page.loading))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            }
        case .failed(let message):
            VStack(spacing: Spacing.md) {
                Text(verbatim: message).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                VButton(L10n.text(K.alerts.ui.retry), tid: "alerts.retry", role: .secondary) {
                    Task { await model.load() }
                }
            }
        case .loaded:
            loaded
        }
    }

    @ViewBuilder private var loaded: some View {
        ForEach(model.partialNotes, id: \.self) { note in
            Text(verbatim: note).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
        }
        if model.rows.isEmpty {
            EmptyState(icon: "bell", title: L10n.text(K.alerts.page.emptyTitle), message: model.emptyText(.all))
        } else {
            filterBar
            Text(verbatim: model.statusText(model.filter))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .accessibilityAddTraits(.isHeader)
            if model.filtered.isEmpty {
                Text(verbatim: model.emptyText(model.filter))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            }
            group(model.activeRows, title: nil)
            group(model.pastRows, title: L10n.text(K.alerts.page.past))
        }
    }

    private var filterBar: some View {
        // Wraps onto further lines instead of scrolling, so no chip is ever cut off at an edge.
        AlertsWrapLayout(spacing: Spacing.sm) {
            ForEach(AlertsFilter.allCases) { filter in
                VChip(
                    title: "\(model.tabTitle(filter)) \(model.count(filter))", tid: "alerts.filter-\(filter.rawValue)",
                    selected: model.filter == filter
                ) { model.filter = filter }
                .accessibilityLabel(
                    L10n.text(
                        K.alerts.page.tabAria, ["label": model.tabTitle(filter), "n": String(model.count(filter))]))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(K.alerts.page.filterLabel))
    }

    @ViewBuilder private func group(_ rows: [WatchRow], title: String?) -> some View {
        if !rows.isEmpty {
            if let title {
                Text(verbatim: title).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(rows) { row in
                WatchCard(
                    row: row, busy: model.busy[row.id], highlighted: model.focusedID == row.id, now: model.currentDate,
                    onCheck: { Task { await model.check(row) } },
                    onLive: { Task { await model.startLiveCheck(row) } },
                    onEdit: { model.editing = row },
                    onTogglePause: { Task { await model.togglePause(row) } },
                    onDelete: { deleting = row }
                )
                .id(row.id)
            }
        }
    }
}
