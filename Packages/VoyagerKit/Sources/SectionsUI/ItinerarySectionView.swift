import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// The day-by-day itinerary with editing: move (sheet or drag and drop), remove and restore, edit activity,
/// place and cost, notes, picking slots into the plan. Layout, edits, notes and picks go through the host's
/// selections (`ItineraryHost`); without a host they live in memory only.
public struct ItinerarySectionView: View {
    let data: JSONValue
    let ctx: SectionContext
    @Environment(\.itineraryHost) private var host
    @Environment(\.telemetryRoute) private var route
    @State private var model: ItineraryEditorModel
    @State private var moveKey: String?
    @State private var editKey: String?

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
        _model = State(initialValue: ItineraryEditorModel(itinerary: data, editable: false))
    }

    public var body: some View {
        Group {
            if model.hasDays { content } else { empty }
        }
        .onAppear {
            model.update(itinerary: data)
            model.attach(host)
        }
        // Selections changed elsewhere (plan loaded, a pick from another section).
        .task(id: host?.selections()) { model.attach(host) }
        .onChange(of: data) { _, new in model.update(itinerary: new) }
        .sheet(item: Binding(get: { moveKey.map(KeyItem.init) }, set: { moveKey = $0?.key })) { item in
            moveSheet(for: item.key)
        }
        .sheet(item: Binding(get: { editKey.map(KeyItem.init) }, set: { editKey = $0?.key })) { item in
            editSheet(for: item.key)
        }
    }

    private struct KeyItem: Identifiable { let key: String; var id: String { key } }

    private var empty: some View {
        Text(verbatim: L10n.text(K.itinerary.section.empty))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let coverage = ItineraryText.linkCoverage(searchData: ctx.searchData, itinerary: model.arranged) {
                LinkCoverageBanner(coverage: coverage, title: ctx.searchData?["import_source"]["title"].string)
            }
            TripMapView(data: model.arranged, ctx: ctx)
            if let total = ItineraryText.cost(model.arranged["total_estimated_cost_usd"]), total > 0 {
                Text(verbatim: L10n.text(K.itinerary.section.estCost, ["cost": ItineraryText.usd(total)]))
                    .font(VFont.body(.subheadline, weight: .medium))
                    .foregroundStyle(Palette.color(.teal, .s700))
            }
            if model.editable { toolbar }
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ForEach(Array(model.scheduledDays.enumerated()), id: \.offset) { _, day in
                    DayView(
                        model: model, day: day,
                        onMove: { moveKey = $0 }, onEdit: { editKey = $0 })
                }
            }
            if model.editable, !model.removed.isEmpty { removedList }
            Text(verbatim: L10n.text(K.itinerary.section.timesNote))
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Toolbar and removed slots

    @ViewBuilder private var toolbar: some View {
        if model.changeCount > 0 || model.canUndo {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.itinerary.toolbar.changes, count: model.changeCount))
                    .font(VFont.body(.caption, weight: .medium)).foregroundStyle(SemanticColor.textMuted)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.sm) { toolbarButtons }
                    VStack(alignment: .leading, spacing: Spacing.xs) { toolbarButtons }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: L10n.text(K.itinerary.toolbar.label)))
        }
    }

    @ViewBuilder private var toolbarButtons: some View {
        VButton(L10n.text(K.itinerary.toolbar.undo), tid: "itinerary.undo", role: .tonal, systemImage: "arrow.uturn.backward") {
            model.undo()
            LiveRegion.announce(L10n.text(K.itinerary.status.undone))
        }
        .disabled(!model.canUndo)
        VButton(L10n.text(K.itinerary.toolbar.reset), tid: "itinerary.reset", role: .tonal, systemImage: "arrow.counterclockwise") {
            model.reset()
            LiveRegion.announce(L10n.text(K.itinerary.status.reset))
        }
        .disabled(model.changeCount == 0)
    }

    private var removedList: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.itinerary.removed.heading))
                .font(VFont.display(.headline)).foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(model.removed.enumerated()), id: \.offset) { _, entry in
                let key = entry["key"].string ?? ""
                let name = model.activityName(key: key, fallback: entry["slot"]["activity"].string)
                HStack {
                    Text(verbatim: name).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                        .strikethrough().fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm)
                    Button {
                        Telemetry.shared.track(.uiTap(tid: "itinerary.restore", route: route))
                        restore(key: key, name: name, day: entry["slot"]["day_number"])
                    } label: {
                        Text(verbatim: L10n.text(K.itinerary.removed.restore))
                            .font(VFont.body(.footnote, weight: .medium)).foregroundStyle(SemanticColor.primary)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: L10n.text(K.itinerary.removed.restoreAria, ["name": name])))
                    .accessibilityIdentifier("itinerary.restore")
                }
            }
            if let message = restoreFailure {
                Text(verbatim: message).font(VFont.body(.caption)).foregroundStyle(SemanticColor.destructive)
            }
        }
    }

    @State private var restoreFailure: String?

    private func restore(key: String, name: String, day: JSONValue) {
        if model.restore(key: key) {
            restoreFailure = nil
            LiveRegion.announce(L10n.text(K.itinerary.status.restored, ["name": name]))
        } else {
            restoreFailure = L10n.text(K.itinerary.removed.noRoom, ["day": ItineraryText.dayNumberText(day)])
        }
    }

    // MARK: Sheets

    private func scheduledSlot(for key: String) -> JSONValue? {
        for day in model.scheduledDays {
            for slot in day["slots"].array ?? [] where slot["key"].string == key { return slot }
        }
        return nil
    }

    @ViewBuilder private func moveSheet(for key: String) -> some View {
        let slot = scheduledSlot(for: key)
        let name = model.activityName(key: key, fallback: slot?["activity"].string)
        MoveSheet(
            name: name, targets: model.targets(for: key),
            onMove: { day, tod in
                let target = model.targets(for: key).first { $0["day_number"].int == day && $0["time_of_day"].string == tod }
                if model.move(key: key, day: day, timeOfDay: tod), let target {
                    LiveRegion.announce(L10n.text(K.itinerary.status.moved, [
                        "name": name,
                        "position": ItineraryText.position(day: target["day_number"], timeOfDay: target["time_of_day"]),
                        "swap": MoveSheet.swapSuffix(K.itinerary.menu.swappedWith, target["swapWith"]),
                    ]))
                }
            },
            onRemove: {
                if model.remove(key: key) {
                    LiveRegion.announce(L10n.text(K.itinerary.status.removed, [
                        "name": name, "day": ItineraryText.dayNumberText(slot?["day_number"] ?? .null),
                    ]))
                }
            })
    }

    @ViewBuilder private func editSheet(for key: String) -> some View {
        let slot = scheduledSlot(for: key)
        let edit = model.edits[key]
        SlotEditor(
            initialActivity: model.activityName(key: key, fallback: slot?["activity"].string),
            initialLocation: edit["location"].string ?? slot?["location"].string ?? "",
            initialCost: ItineraryText.cost(edit["cost"].isNull ? (slot?["estimated_cost_usd"] ?? .null) : edit["cost"]),
            initialNote: model.notes[key].string ?? "",
            onSave: { activity, location, cost, note in
                model.setEdit(key: key, field: "activity", value: .string(activity))
                model.setEdit(key: key, field: "location", value: .string(location))
                model.setEdit(key: key, field: "cost", value: cost.map { .number($0) } ?? .null)
                model.setNote(key: key, text: note)
            })
    }
}

/// "Planned around N places from <your link>: M of N are in your itinerary", with the ones that did not fit.
struct LinkCoverageBanner: View {
    let coverage: ItineraryLinkCoverage
    let title: String?
    @State private var showMissing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: summary)
                .font(VFont.body(.footnote, weight: .medium))
                .foregroundStyle(Palette.color(.amber, .s700))
                .fixedSize(horizontal: false, vertical: true)
            if coverage.state == .ready, !coverage.missing.isEmpty {
                Button {
                    showMissing.toggle()
                } label: {
                    let toggleKey = showMissing ? K.misc.linkPlan.didntFit : K.misc.linkPlan.didntFitShow
                    Text(verbatim: L10n.text(toggleKey, ["n": String(coverage.missing.count)]))
                        .font(VFont.body(.footnote, weight: .medium)).foregroundStyle(SemanticColor.primary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("itinerary.link.missing")
                if showMissing {
                    Text(verbatim: L10n.text(K.misc.linkPlan.missing, ["names": coverage.missing.joined(separator: ", ")]))
                        .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.color(.amber, .s100), in: RoundedRectangle(cornerRadius: Radius.itemCard))
        .accessibilityElement(children: .contain)
    }

    /// The sentence names the source in plain text (the web links it; the Results host shows the link).
    private var summary: String {
        let source = title.flatMap { $0.isEmpty ? nil : $0 } ?? L10n.text(K.misc.linkPlan.yourLink)
        let total = coverage.total
        let key: LKey
        var args: [String: String] = [:]
        switch coverage.state {
        case .pending: key = K.misc.linkPlan.fitting
        case .ready where coverage.inItinerary == total: key = K.misc.linkPlan.all
        case .ready:
            key = K.misc.linkPlan.some
            args["inItinerary"] = String(coverage.inItinerary)
        }
        // `<src/>` marks where the web puts the link; plain text names the source there.
        return L10n.text(key, args, count: total).replacingOccurrences(of: "<src/>", with: source)
    }
}
