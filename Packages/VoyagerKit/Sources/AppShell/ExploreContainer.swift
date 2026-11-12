import DesignSystem
import FeatureChat
import FeatureCompare
import FeatureDiscover
import FeatureImport
import FeatureSearch
import L10n
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The Explore tab: a segmented picker over the five modes (web order) hosting each entry view, plus a Near me
/// button. In the iPad sidebar the modes are rows there, so the picker is hidden.
struct ExploreContainer: View {
    let env: AppEnvironment
    let router: AppRouter
    var showsPicker = true

    var body: some View {
        let mode = router.exploreMode
        VStack(spacing: 0) {
            if showsPicker {
                Picker(selection: modeBinding) {
                    ForEach(ExploreMode.allCases, id: \.self) { item in
                        Text(verbatim: TabInfo.modeTitle(item)).tag(item)
                    }
                } label: {
                    Text(verbatim: TabInfo.title(.explore))
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .accessibilityIdentifier("explore.modes")
            }
            content(mode)
                .id(mode)
                .telemetryRoute(TelemetryRouteName.template(for: .explore(mode)))
                .telemetryScreen(TelemetryRouteName.template(for: .explore(mode)))
        }
        .navigationTitle(Text(verbatim: TabInfo.modeTitle(mode)))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    router.open(.nearby)
                } label: {
                    Label(L10n.text(K.common.nav.nearby), systemImage: "location")
                }
                .accessibilityIdentifier("explore.nearby")
            }
        }
    }

    private var modeBinding: Binding<ExploreMode> {
        mainBinding(get: { router.exploreMode }, set: { router.open(.explore($0)) })
    }

    @ViewBuilder private func content(_ mode: ExploreMode) -> some View {
        switch mode {
        case .search: SearchFormView(env: env, prefill: nil)
        case .chat: ChatRootView(env: env)
        case .compare: CompareView(env: env)
        case .link: ImportView(env: env, initialURL: router.importURL)
        case .discover: DiscoverView(env: env)
        }
    }
}
