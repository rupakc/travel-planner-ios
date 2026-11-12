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
    @State private var visited: Set<ExploreMode> = []

    var body: some View {
        let mode = router.exploreMode
        VStack(spacing: 0) {
            if showsPicker { modeChips }
            ZStack {
                // Visited modes stay alive (hidden), so a half-filled form survives a mode switch.
                ForEach(ExploreMode.allCases.filter { visited.contains($0) || $0 == mode }, id: \.self) { item in
                    let active = item == mode
                    content(item)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                        .accessibilityHidden(!active)
                        .telemetryRoute(TelemetryRouteName.template(for: .explore(item)))
                        .modifier(ActiveScreen(template: TelemetryRouteName.template(for: .explore(item)), active: active))
                }
            }
            .onAppear { visited.insert(mode) }
            .onChange(of: mode) { _, new in visited.insert(new) }
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

    /// Scrolling chips: five modes never truncate, at any Dynamic Type size.
    private var modeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(ExploreMode.allCases, id: \.self) { item in
                    let selected = item == router.exploreMode
                    Button {
                        router.open(.explore(item))
                    } label: {
                        Text(verbatim: TabInfo.modeTitle(item))
                            .font(VFont.body(.subheadline, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .foregroundStyle(selected ? SemanticColor.onPrimary : SemanticColor.text)
                            .background(selected ? SemanticColor.primary : SemanticColor.surfaceRaised, in: Capsule())
                            .overlay { Capsule().strokeBorder(SemanticColor.border, lineWidth: selected ? 0 : 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("explore.mode.\(item.rawValue)")
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
        .accessibilityIdentifier("explore.modes")
    }

    @ViewBuilder private func content(_ mode: ExploreMode) -> some View {
        switch mode {
        case .search: SearchFormView(env: env, prefill: nil)
        case .chat: ChatRootView(env: env)
        case .compare: CompareView(env: env)
        case .link: ImportView(env: env, initialURL: router.importURL).id(router.importURL)
        case .discover: DiscoverView(env: env)
        }
    }
}

/// `telemetryScreen` only for the visible mode.
private struct ActiveScreen: ViewModifier {
    let template: String
    let active: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if active { content.telemetryScreen(template) } else { content }
    }
}
