import CoreLocation
import DesignSystem
import L10n
import MapKit
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// The trip on a map: numbered stops, coloured by day, from the slots' `lat`/`lng`. `data` is the itinerary
/// (arranged, so moves show). The map is only built while expanded; it starts collapsed on iPhone and open in
/// the iPad detail column. "Open in Maps" hands the selected stop to Apple Maps.
public struct TripMapView: View {
    let data: JSONValue
    let ctx: SectionContext
    /// `itinerary_edits`, so renamed activities show their new name.
    let edits: JSONValue
    @State private var expanded: Bool
    @State private var selected: Int?
    @Environment(\.telemetryRoute) private var route

    public init(data: JSONValue, ctx: SectionContext, edits: JSONValue = .null) {
        self.data = data
        self.ctx = ctx
        self.edits = edits
        _expanded = State(initialValue: Self.initiallyExpanded(layout: ctx.layout))
    }

    public struct Stop: Identifiable, Equatable, Sendable {
        public let id: Int
        public let name: String
        public let coordinate: CLLocationCoordinate2D
        public let day: Int
        public let dayLabel: String
        public let fromLink: Bool

        public static func == (lhs: Stop, rhs: Stop) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.day == rhs.day
                && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
        }
    }

    /// Stops in itinerary order. A slot needs a finite `lat` in -90...90 and `lng` in -180...180 (loose AI
    /// JSON: strings, nulls and out-of-range values are skipped, never trapped on).
    public static func stops(from itinerary: JSONValue, edits: JSONValue = .null) -> [Stop] {
        var stops: [Stop] = []
        for (index, day) in (itinerary["days"].array ?? []).enumerated() {
            let dayNumber = day["day_number"].int ?? index + 1
            let city = day["city"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            for slot in day["slots"].array ?? [] {
                guard let lat = slot["lat"].double, let lng = slot["lng"].double,
                    lat.isFinite, lng.isFinite, (-90...90).contains(lat), (-180...180).contains(lng)
                else { continue }
                let time = ItineraryText.timeOfDay(slot["time_of_day"].string)
                let label =
                    city.flatMap { $0.isEmpty ? nil : $0 }.map {
                        L10n.text(K.itinerary.map.dayLineCity, ["day": String(dayNumber), "city": $0, "time": time])
                    } ?? L10n.text(K.itinerary.map.dayLine, ["day": String(dayNumber), "time": time])
                stops.append(Stop(
                    id: stops.count, name: edits[slot["key"].string ?? ""]["activity"].string.flatMap { $0.isEmpty ? nil : $0 }
                        ?? slot["activity"].string ?? slot["location"].string ?? "",
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), day: dayNumber, dayLabel: label,
                    fromLink: slot["from_link"].isTruthy))
            }
        }
        return stops
    }

    public static func initiallyExpanded(layout: LayoutClass) -> Bool { layout == .regular }

    /// The one rule for building the (expensive) map: only while expanded and with something to show.
    public static func buildsMap(expanded: Bool, stopCount: Int) -> Bool { expanded && stopCount > 0 }

    static let dayFamilies: [Family] = [.teal, .amber, .violet, .rose, .sky, .emerald]

    static func color(forDay day: Int) -> Color {
        let index = ((day - 1) % dayFamilies.count + dayFamilies.count) % dayFamilies.count
        return Palette.color(dayFamilies[index], .s600)
    }

    public var body: some View {
        let stops = Self.stops(from: data, edits: edits)
        if !stops.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button {
                    expanded.toggle()
                    Telemetry.shared.track(.uiToggle(tid: "itinerary.map", route: route, on: expanded))
                } label: {
                    HStack {
                        Label { Text(verbatim: L10n.text(K.search.map.aria)) } icon: { Image(systemName: "map") }
                            .font(VFont.body(.subheadline, weight: .medium))
                            .foregroundStyle(SemanticColor.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Spacing.sm)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(SemanticColor.textMuted).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("itinerary.map")
                if Self.buildsMap(expanded: expanded, stopCount: stops.count) {
                    StopsMap(stops: stops, selected: $selected)
                        .frame(height: ctx.layout == .regular ? 360 : 260)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.itemCard))
                    detail(stops)
                }
            }
        }
    }

    @ViewBuilder private func detail(_ stops: [Stop]) -> some View {
        let stop = stops.first { $0.id == selected } ?? stops[0]
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: stop.name).font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: stop.dayLabel).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            if stop.fromLink {
                Text(verbatim: L10n.text(K.itinerary.map.fromLink)).font(VFont.body(.caption, weight: .medium))
                    .foregroundStyle(Palette.color(.amber, .s700))
            }
            VButton(L10n.text(K.mobile.maps.open), tid: "itinerary.map.open", role: .tonal, systemImage: "arrow.up.right.square") {
                Self.openInMaps(stop)
            }
        }
    }

    static func openInMaps(_ stop: Stop) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        item.name = stop.name
        item.openInMaps()
    }
}

private struct StopsMap: View {
    let stops: [TripMapView.Stop]
    @Binding var selected: Int?

    var body: some View {
        Map(selection: $selected) {
            ForEach(stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate) {
                    Text(verbatim: String(stop.id + 1))
                        .font(VFont.body(.caption2, weight: .bold))
                        .foregroundStyle(SemanticColor.onPrimary)
                        .frame(width: 24, height: 24)
                        .background(TripMapView.color(forDay: stop.day), in: Circle())
                        .overlay { Circle().strokeBorder(SemanticColor.onPrimary, lineWidth: stop.fromLink ? 3 : 1.5) }
                        .accessibilityLabel(Text(verbatim: "\(stop.id + 1). \(stop.name)"))
                }
                .tag(stop.id)
            }
            MapPolyline(coordinates: stops.map(\.coordinate))
                .stroke(SectionAccent.color(for: "itinerary").opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        }
    }
}
