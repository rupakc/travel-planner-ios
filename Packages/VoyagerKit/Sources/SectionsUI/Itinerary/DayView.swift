import DesignSystem
import Domain
import L10n
import SwiftUI
import VoyagerModel

/// One arranged day: heading with its estimated cost, schedule warnings, its slots in order (plus "Free time"
/// rows for standard times nobody occupies, as drop targets), and the extra places from the user's link.
struct DayView: View {
    let model: ItineraryEditorModel
    let day: JSONValue
    let onMove: (String) -> Void
    let onEdit: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Row: Identifiable {
        case slot(JSONValue, Int)
        case free(String)
        var id: String {
            switch self {
            case .slot(let slot, let index): "slot-\(slot["key"].string ?? "")-\(index)"
            case .free(let tod): "free-\(tod)"
            }
        }
    }

    /// Slots grouped by standard time of day, a "Free time" row for each empty one (only on days that have a
    /// standard-time slot and only while editing), then any slot with an unusual time.
    static func rows(for day: JSONValue, editable: Bool) -> [Row] {
        let slots = day["slots"].array ?? []
        let standard = ItineraryLayout.times
        guard slots.contains(where: { standard.contains($0["time_of_day"].string ?? "") }) else {
            return slots.enumerated().map { .slot($0.element, $0.offset) }
        }
        var rows: [Row] = []
        for tod in standard {
            let matching = slots.enumerated().filter { $0.element["time_of_day"].string == tod }
            if matching.isEmpty {
                if editable { rows.append(.free(tod)) }
            } else {
                rows += matching.map { .slot($0.element, $0.offset) }
            }
        }
        rows += slots.enumerated().filter { !standard.contains($0.element["time_of_day"].string ?? "") }
            .map { .slot($0.element, $0.offset) }
        return rows
    }

    var body: some View {
        let rows = Self.rows(for: day, editable: model.editable)
        let ordered = Schedule.listedInScheduleOrder(day)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            ForEach(Array((day["schedule_warnings"].array ?? []).compactMap(\.string).enumerated()), id: \.offset) { _, warning in
                Label { Text(verbatim: L10n.text(K.itinerary.section.tightSchedule) + ": " + warning) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(VFont.body(.caption))
                .foregroundStyle(Palette.color(.amber, .s700))
                .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Spacing.sm) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    switch row {
                    case .slot(let slot, _):
                        SlotRow(
                            model: model, slot: slot, dayNumber: day["day_number"], showsTransit: ordered,
                            isLast: index == rows.count - 1,
                            onMove: { onMove(slot["key"].string ?? "") }, onEdit: { onEdit(slot["key"].string ?? "") }
                        )
                        .modifier(SlotDrop(model: model, day: day["day_number"].int, timeOfDay: slot["time_of_day"].string))
                    case .free(let tod):
                        FreeTimeRow(timeOfDay: tod, isLast: index == rows.count - 1)
                            .modifier(SlotDrop(model: model, day: day["day_number"].int, timeOfDay: tod))
                    }
                }
            }
            extras
        }
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm))
        return layout {
            Text(verbatim: ItineraryText.dayHeading(day))
                .font(VFont.display(.headline))
                .foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.sm) }
            if let cost = ItineraryText.cost(day["daily_estimated_cost_usd"]), cost > 0 {
                Text(verbatim: L10n.text(K.itinerary.cost.est, ["cost": ItineraryText.usd(cost)]))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    @ViewBuilder private var extras: some View {
        let names = (day["link_extras"].array ?? []).compactMap { $0["name"].string }
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.itinerary.extras.label)).font(VFont.body(.caption, weight: .semibold))
                Text(verbatim: L10n.text(K.itinerary.extras.fit, ["names": names.joined(separator: ", ")], count: names.count))
                    .font(VFont.body(.caption))
            }
            .foregroundStyle(Palette.color(.amber, .s700))
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FreeTimeRow: View {
    let timeOfDay: String
    let isLast: Bool

    var body: some View {
        ItineraryTimelineRail(time: nil, isLast: isLast, accent: SemanticColor.border) {
            Text(verbatim: ItineraryText.timeOfDay(timeOfDay) + " · " + L10n.text(K.itinerary.section.freeTime))
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.textMuted)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.itemCard)
                        .strokeBorder(SemanticColor.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
        }
    }
}

/// Drops a dragged slot onto a position; only a valid target moves anything (`move` checks it again).
private struct SlotDrop: ViewModifier {
    let model: ItineraryEditorModel
    let day: Int?
    let timeOfDay: String?
    @State private var targeted = false

    func body(content: Content) -> some View {
        if model.editable, let day, let timeOfDay {
            content
                .dropDestination(for: String.self) { items, _ in
                    guard let key = items.compactMap(ItineraryDrag.key(from:)).first else { return false }
                    return model.move(key: key, day: day, timeOfDay: timeOfDay)
                } isTargeted: { targeted = $0 }
                .overlay {
                    if targeted {
                        RoundedRectangle(cornerRadius: Radius.itemCard)
                            .strokeBorder(SectionAccent.color(for: "itinerary"), lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
        } else {
            content
        }
    }
}
