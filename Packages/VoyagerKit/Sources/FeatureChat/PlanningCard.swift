import DesignSystem
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerModel

private struct ShowsMapKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Snapshots turn the trip map off: it is another module's view and would change their references.
    var chatShowsMap: Bool {
        get { self[ShowsMapKey.self] }
        set { self[ShowsMapKey.self] = newValue }
    }
}

/// A planning stream in a message: the trip map, the "building" spinner, then the day-by-day plan
/// (`comprehensive_itinerary`, api-contract §4.3).
struct PlanningCard: View {
    let planning: PlanningState
    let ctx: SectionContext
    @State private var expanded: Set<Int> = [1]
    @Environment(\.chatShowsMap) private var showsMap

    private var days: [JSONValue] { planning.itinerary?["days"].array ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header
            if let map = planning.tripMap, showsMap {
                TripMapView(data: map, ctx: ctx)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.itemCard))
            }
            status
            if !days.isEmpty {
                expandToggle
                // A plain stack (not lazy): the plan is at most a few weeks of days.
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        DayCard(day: day, number: day["day_number"].int ?? index + 1, expanded: binding(for: day, index: index))
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SemanticColor.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.itemCard))
        .overlay { RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.planning")
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "map").foregroundStyle(SemanticColor.primary).accessibilityHidden(true)
            Text(verbatim: title)
                .font(VFont.display(.headline))
                .foregroundStyle(SemanticColor.text)
        }
    }

    private var title: String {
        if !days.isEmpty { return L10n.text(K.chat.trip.daysItinerary, ["n": String(days.count)]) }
        return planning.destination ?? L10n.text(K.chat.bubble.planning)
    }

    @ViewBuilder private var status: some View {
        if let error = planning.itineraryError {
            Text(verbatim: error.isEmpty ? L10n.text(K.chat.trip.buildFailed) : error)
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
        } else if planning.itinerary == nil, !planning.done {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text(verbatim: L10n.text(planning.generating ? K.chat.section.building : K.chat.trip.plotting))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    private var expandToggle: some View {
        let allOpen = expanded.count >= days.count
        return VButton(
            L10n.text(allOpen ? K.chat.trip.collapseAll : K.chat.trip.expandAll), tid: "chat.planning.expandAll", role: .tonal
        ) {
            expanded = allOpen ? [] : Set(days.enumerated().map { $0.element["day_number"].int ?? $0.offset + 1 })
        }
    }

    private func binding(for day: JSONValue, index: Int) -> Binding<Bool> {
        let number = day["day_number"].int ?? index + 1
        return Binding(
            get: { expanded.contains(number) },
            set: { if $0 { expanded.insert(number) } else { expanded.remove(number) } })
    }
}

/// One itinerary day: header (number, city, theme) and, open, hotel, the three parts of the day, sights, dining.
private struct DayCard: View {
    let day: JSONValue
    let number: Int
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: L10n.text(K.chat.itinerary.day, ["n": String(number)]))
                            .font(VFont.body(.subheadline, weight: .semibold))
                        if let subtitle { Text(verbatim: subtitle).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted) }
                    }
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }
                .foregroundStyle(SemanticColor.text)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.planning.day.\(number)")
            if expanded { details }
        }
        .padding(.horizontal, Spacing.md)
        .background(SemanticColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.input))
    }

    private var subtitle: String? {
        let parts = [day["city"].string, day["theme"].string].compactMap { $0 }.filter { !$0.isEmpty }
        let text = parts.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if day["is_travel_day"].bool == true {
                line(symbol: "airplane", text: L10n.text(K.chat.trip.travelDay))
            }
            if let hotel = day["hotel"]["name"].string {
                line(symbol: "bed.double", text: hotel)
            }
            slot("morning", K.chat.itinerary.timeOfDay.morning)
            slot("afternoon", K.chat.itinerary.timeOfDay.afternoon)
            slot("evening", K.chat.itinerary.timeOfDay.evening)
            names(day["places_to_see"].array, symbol: "mappin.and.ellipse", key: "name")
            names(day["dining"].array, symbol: "fork.knife", key: "name")
        }
        .padding(.bottom, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func slot(_ key: String, _ label: LKey) -> some View {
        let value = day[key]
        if let activity = value["activity"].string, !activity.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: L10n.text(label)).font(VFont.body(.caption, weight: .semibold)).foregroundStyle(SemanticColor.textMuted)
                Text(verbatim: [activity, value["place"].string].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            }
        }
    }

    @ViewBuilder private func names(_ items: [JSONValue]?, symbol: String, key: String) -> some View {
        let texts = (items ?? []).compactMap { $0[key].string }.filter { !$0.isEmpty }
        if !texts.isEmpty { line(symbol: symbol, text: texts.joined(separator: ", ")) }
    }

    private func line(symbol: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: symbol).foregroundStyle(SemanticColor.textMuted).accessibilityHidden(true)
            Text(verbatim: text).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
        }
    }
}
