import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv

/// Near me: places to see, eat, shop and stay around the user (the web `NearbyPage`).
public struct NearbyView: View {
    @State private var model: NearbyModel
    @Environment(\.openURL) private var openURL

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: NearbyModel(env: env, location: CoreLocationProvider()))
    }

    @MainActor init(model: NearbyModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text(verbatim: L10n.text(K.misc.nearby.subtitle))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
                content
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
        }
        .navigationTitle(L10n.text(K.misc.nearby.title))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.begin() }
        .accessibilityIdentifier("nearby.root")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .intro:
            card(
                title: L10n.text(K.mobile.permissions.locationTitle), message: L10n.text(K.mobile.permissions.locationBody)
            ) {
                VButton(L10n.text(K.misc.nearby.useLocation), tid: "nearby.use-location", systemImage: "location") {
                    Task { await model.useLocation() }
                }
            }
        case .denied:
            card(title: L10n.text(K.misc.nearby.geoErrorTitle), message: L10n.text(K.mobile.permissions.locationBody)) {
                if let url = model.settingsURL {
                    VButton(L10n.text(K.mobile.permissions.openSettings), tid: "nearby.open-settings", systemImage: "gear") {
                        openURL(url)
                    }
                }
            }
        case .locating:
            progress(L10n.text(K.misc.nearby.finding))
        case .loading:
            progress(L10n.text(K.misc.nearby.looking))
        case .failed(let message):
            card(title: L10n.text(K.misc.nearby.apiErrorTitle), message: message) {
                VButton(L10n.text(K.misc.nearby.tryAgain), tid: "nearby.retry", role: .secondary) {
                    Task { await model.load() }
                }
            }
        case .loaded:
            if let result = model.result { loaded(result) }
        }
    }

    private func card<Actions: View>(title: String, message: String, @ViewBuilder actions: () -> Actions) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: title)
                    .font(VFont.display(.headline))
                    .foregroundStyle(SemanticColor.text)
                Text(verbatim: message)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: Spacing.md) {
            ProgressView()
            Text(verbatim: text)
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.textMuted)
        }
        .accessibilityElement(children: .combine)
    }

    private func loaded(_ result: NearbyResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text(verbatim: L10n.text(K.misc.nearby.found, ["place": result.placeName], count: result.count))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.text)
                Spacer(minLength: Spacing.sm)
                VButton(L10n.text(K.misc.nearby.refresh), tid: "nearby.refresh", role: .tonal, systemImage: "arrow.clockwise") {
                    Task { await model.load() }
                }
            }
            ForEach(result.groups) { group in
                groupView(group)
            }
            if result.isV2 { footer(result) }
        }
    }

    private func groupView(_ group: NearbyGroup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: group.title)
                .font(VFont.display(.title3))
                .foregroundStyle(SemanticColor.text)
            if group.rows.isEmpty, let empty = group.emptyText {
                Text(verbatim: empty)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
            }
            ForEach(group.rows) { row in
                rowView(row)
            }
        }
    }

    private func rowView(_ row: NearbyRow) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: row.name)
                    .font(VFont.body(.headline))
                    .foregroundStyle(SemanticColor.text)
                if let summary = row.summary {
                    Text(verbatim: summary)
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let url = row.mapsURL {
                        VButton(L10n.text(K.misc.nearby.openMaps), tid: "nearby.open-maps", role: .tonal, systemImage: "map") {
                            model.didOpenMaps(row)
                            openURL(url)
                        }
                        .accessibilityLabel(L10n.text(K.misc.nearby.openMapsAria, ["name": row.name]))
                    }
                    VButton(
                        model.isInPlan(row) ? L10n.text(K.results.plan.inPlan) : L10n.text(K.results.plan.add),
                        tid: "nearby.plan", role: .secondary,
                        systemImage: model.isInPlan(row) ? "checkmark" : "plus"
                    ) {
                        model.togglePlan(row)
                    }
                }
            }
        }
    }

    private func footer(_ result: NearbyResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let attribution = result.attribution, !attribution.isEmpty {
                Text(verbatim: L10n.text(K.misc.nearby.attribution).replacingOccurrences(of: "<src/>", with: attribution))
                    .font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.textMuted)
            }
            if !result.sources.isEmpty {
                Text(verbatim: L10n.text(K.misc.nearby.sources))
                    .font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.textMuted)
                ForEach(Array(result.sources.enumerated()), id: \.offset) { _, source in
                    if let uri = source.uri, let url = URL(string: uri), url.scheme?.lowercased() == "https" {
                        Link(destination: url) {
                            Text(verbatim: source.title ?? url.host() ?? uri).font(VFont.body(.caption))
                        }
                    }
                }
            }
        }
    }
}
