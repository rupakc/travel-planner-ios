import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// The drag payload of a slot: a private prefix, so a stray string drop never moves anything.
enum ItineraryDrag {
    static let prefix = "voyager.itinerary.slot:"
    static func payload(_ key: String) -> String { prefix + key }
    static func key(from payload: String) -> String? {
        payload.hasPrefix(prefix) ? String(payload.dropFirst(prefix.count)) : nil
    }
}

/// One scheduled slot: time rail, activity (with edits applied), place, estimated cost, link badge, note,
/// travel from the stop above, and the actions (move, edit, add to plan).
struct SlotRow: View {
    let model: ItineraryEditorModel
    let slot: JSONValue
    let dayNumber: JSONValue
    let showsTransit: Bool
    let isLast: Bool
    let onMove: () -> Void
    let onEdit: () -> Void
    @Environment(\.telemetryRoute) private var route

    private var key: String { slot["key"].string ?? "" }
    private var edit: JSONValue { model.edits[key] }
    private var name: String { model.activityName(key: key, fallback: slot["activity"].string) }
    private var location: String? {
        let text = (edit["location"].string ?? slot["location"].string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
    private var cost: Double? { ItineraryText.cost(edit["cost"].isNull ? slot["estimated_cost_usd"] : edit["cost"]) }
    private var note: String? {
        let text = model.notes[key].string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
    private var isEdited: Bool { edit["activity"].isTruthy || edit["location"].isTruthy || !edit["cost"].isNull }

    var body: some View {
        ItineraryTimelineRail(
            time: slot["start_time"].string, isLast: isLast, accent: SectionAccent.color(for: "itinerary")
        ) {
            card
        }
        .accessibilityElement(children: .contain)
    }

    private var card: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(verbatim: ItineraryText.timeOfDay(slot["time_of_day"].string))
                        .font(VFont.body(.caption, weight: .medium))
                        .foregroundStyle(SemanticColor.textMuted)
                    if let range = Schedule.timeRange(slot) {
                        Text(verbatim: range).font(VFont.body(.caption)).monospacedDigit()
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                }
                Text(verbatim: name)
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                if slot["from_link"].isTruthy { linkBadge }
                if let location {
                    Label { Text(verbatim: location) } icon: { Image(systemName: "mappin.and.ellipse") }
                        .font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let cost {
                    Text(verbatim: L10n.text(K.itinerary.cost.est, ["cost": ItineraryText.usd(cost)]))
                        .font(VFont.body(.caption, weight: .medium))
                        .foregroundStyle(SemanticColor.textMuted)
                }
                if let note {
                    Text(verbatim: note).font(VFont.body(.caption)).italic()
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showsTransit, let travel = Schedule.transitLabel(slot["transit_from_prev"], strings: ItineraryText.transitStrings) {
                    Text(verbatim: travel).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                }
                actions
            }
        }
        .modifier(SlotDrag(key: key, enabled: !model.targets(for: key).isEmpty))
    }

    private var linkBadge: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(K.misc.fromLink.chip))
                .font(VFont.body(.caption2, weight: .semibold))
                .foregroundStyle(Palette.color(.amber, .s700))
                .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                .background(Palette.color(.amber, .s100), in: Capsule())
                .overlay { Capsule().strokeBorder(Palette.color(.amber, .s200), lineWidth: 1) }
            if let quote = slot["link_quote"].string, !quote.isEmpty {
                Text(verbatim: quote).font(VFont.body(.caption)).italic().foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { buttons }
            VStack(alignment: .leading, spacing: Spacing.xs) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        let picked = model.isPicked(key: key)
        if model.editable {
            if !model.targets(for: key).isEmpty {
                actionButton(
                    L10n.text(K.itinerary.action.move), "arrow.left.arrow.right", tid: "itinerary.move",
                    label: L10n.text(K.itinerary.aria.move, ["name": name]), action: onMove)
            }
            actionButton(
                L10n.text(isEdited || note != nil ? K.itinerary.action.edited : K.itinerary.action.edit), "pencil",
                tid: "itinerary.edit", label: L10n.text(K.itinerary.aria.edit, ["name": name]), action: onEdit)
        }
        if model.editable {
            actionButton(
                L10n.text(picked ? K.itinerary.action.inPlan : K.itinerary.action.plan), picked ? "checkmark.circle.fill" : "plus.circle",
                tid: "itinerary.plan",
                label: L10n.text(picked ? K.itinerary.aria.removeFromPlan : K.itinerary.aria.addToPlan, ["name": name])
            ) {
                model.togglePick(slot, dayNumber: dayNumber)
            }
        }
    }

    private func actionButton(
        _ title: String, _ symbol: String, tid: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: tid, route: route))
            action()
        } label: {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }
                .font(VFont.body(.footnote, weight: .medium))
                .foregroundStyle(SemanticColor.primary)
                .padding(.horizontal, Spacing.sm)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityIdentifier(tid)
    }
}

/// Drag (long-press lift on iPhone, immediate on iPad pointer/touch) only for slots with somewhere to go.
private struct SlotDrag: ViewModifier {
    let key: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(ItineraryDrag.payload(key))
        } else {
            content
        }
    }
}
