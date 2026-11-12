import DesignSystem
import Domain
import L10n
import SwiftUI

struct FeaturesSection: View {
    let model: SettingsModel

    var body: some View {
        SettingsGroup(title: L10n.text(K.mobile.settings.features)) {
            Text(verbatim: L10n.text(K.mobile.settings.featuresHint))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            ForEach(FeatureCatalogue.all) { feature in
                SettingsToggleRow(
                    title: Self.title(feature.id), hint: nil, tid: "settings.feature.\(feature.id)",
                    isOn: Binding(get: { model.isFeatureOn(feature.id) }, set: { model.setFeature(feature.id, on: $0) }))
            }
        }
    }

    /// The same names the Trips tiles use.
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
}
