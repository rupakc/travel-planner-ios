import SwiftUI
import VoyagerModel

private struct RouterKey: EnvironmentKey {
    static var defaultValue: (any AppRouting)? { nil }
}

private struct TelemetryRouteKey: EnvironmentKey {
    static var defaultValue: String { "/other" }
}

extension EnvironmentValues {
    /// Cross-feature navigation (`router?.open(Route)`); `nil` in previews and snapshots.
    public var router: (any AppRouting)? {
        get { self[RouterKey.self] }
        set { self[RouterKey.self] = newValue }
    }

    /// The route template of the screen the view is on (`/results`, `/plans/:id`), used by `uiTap`.
    public var telemetryRoute: String {
        get { self[TelemetryRouteKey.self] }
        set { self[TelemetryRouteKey.self] = newValue }
    }
}

extension View {
    /// Sets `telemetryRoute` for this subtree (a route template, never a raw path).
    public func telemetryRoute(_ template: String) -> some View {
        environment(\.telemetryRoute, template)
    }

    public func router(_ router: (any AppRouting)?) -> some View {
        environment(\.router, router)
    }
}
