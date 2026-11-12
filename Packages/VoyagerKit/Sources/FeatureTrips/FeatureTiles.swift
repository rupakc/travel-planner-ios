import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// One tile of the Trips tab: a catalogue feature that is switched on for this traveller.
struct FeatureTile: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let route: Route

    /// `FeatureCatalogue.visible` for the traveller types and the user's own switches, in catalogue order.
    @MainActor
    static func visible(in env: AppEnvironment) -> [FeatureTile] {
        let types = env.device.travellerTypes.compactMap(TravellerType.init(rawValue:))
        let shown = FeatureCatalogue.visible(
            types: types, enabled: env.device.featureEnabled, disabled: env.device.featureDisabled)
        return FeatureCatalogue.all.filter { shown.contains($0.id) }.map { feature in
            FeatureTile(id: feature.id, title: title(feature.id), icon: icon(feature.id), route: route(feature.id))
        }
    }

    static func title(_ id: String) -> String {
        switch id {
        case "chat": L10n.text(K.common.nav.chat)
        case "visa_checker": L10n.text(K.results.agents.visa.label)
        case "deal_alerts": L10n.text(K.common.nav.alerts)
        case "best_value": L10n.text(K.mobile.trips.bestValue)
        case "budget_planner": L10n.text(K.mobile.trips.budgetPlanner)
        case "compare": L10n.text(K.search.modes.compare)
        case "surprise_me": L10n.text(K.search.modes.discover)
        case "import_link": L10n.text(K.search.modes.import)
        case "near_me": L10n.text(K.common.nav.nearby)
        case "itinerary_editor": L10n.text(K.results.agents.itinerary.label)
        case "walking_tours": L10n.text(K.results.agents.walking_tours.label)
        case "events": L10n.text(K.results.agents.events.label)
        case "packing_list": L10n.text(K.results.agents.packing_list.label)
        case "emergency_card": L10n.text(K.results.agents.emergency_card.label)
        case "trip_health_check": L10n.text(K.results.agents.stress_test.label)
        case "forex": L10n.text(K.results.agents.forex.label)
        case "sim": L10n.text(K.results.agents.sim.label)
        case "accessibility_info": L10n.text(K.mobile.trips.accessibility)
        default: id
        }
    }

    static func icon(_ id: String) -> String {
        switch id {
        case "chat": "bubble.left.and.bubble.right"
        case "visa_checker": "checkmark.seal"
        case "deal_alerts": "bell"
        case "best_value": "hand.thumbsup"
        case "budget_planner": "creditcard"
        case "compare": "rectangle.split.2x1"
        case "surprise_me": "sparkles"
        case "import_link": "link"
        case "near_me": "location"
        case "itinerary_editor": "calendar"
        case "walking_tours": "figure.walk"
        case "events": "ticket"
        case "packing_list": "suitcase"
        case "emergency_card": "cross.case"
        case "trip_health_check": "heart.text.square"
        case "forex": "dollarsign.circle"
        case "sim": "simcard"
        case "accessibility_info": "figure.roll"
        default: "square.grid.2x2"
        }
    }

    /// Where a tap goes; features without a screen of their own start a search, where they live.
    static func route(_ id: String) -> Route {
        switch id {
        case "chat": .explore(.chat)
        case "compare": .explore(.compare)
        case "surprise_me": .explore(.discover)
        case "import_link": .importLink(nil)
        case "near_me": .nearby
        case "deal_alerts": .alerts(kind: nil, watchID: nil)
        default: .explore(.search)
        }
    }
}

/// The catalogue tiles in a two-column grid (stacks, not a lazy grid: it also renders in hosted snapshots).
struct FeatureTiles: View {
    let tiles: [FeatureTile]
    let onOpen: (Route) -> Void
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        let rows = stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0..<min($0 + 2, tiles.count)]) }
        VStack(spacing: Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Spacing.sm) {
                    ForEach(row) { tile in tileView(tile) }
                    if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }

    private func tileView(_ tile: FeatureTile) -> some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: "trips.tile.\(tile.id)", route: route))
            onOpen(tile.route)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: tile.icon)
                    .foregroundStyle(SemanticColor.primary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(verbatim: tile.title)
                    .font(VFont.body(.subheadline, weight: .medium))
                    .foregroundStyle(SemanticColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.itemCard))
            .overlay { RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border) }
            .contentShape(RoundedRectangle(cornerRadius: Radius.itemCard))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trips.tile.\(tile.id)")
    }
}
