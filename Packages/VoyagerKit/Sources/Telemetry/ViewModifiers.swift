import Foundation
import os
import SwiftUI

/// Tracks which screens are visible so `screen_view` carries a referrer and `screen_time` is exact.
/// Screens appear and disappear in either order during navigation, so state is per route.
final class ScreenTracker: Sendable {
    static let shared = ScreenTracker(telemetry: .shared, now: { Date() })

    private struct State: Sendable {
        var last: String?
        /// Visible routes; the value is when the clock started, `nil` while the app is in the background.
        var visible: [String: Date?] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let telemetry: Telemetry
    private let now: @Sendable () -> Date

    init(telemetry: Telemetry, now: @escaping @Sendable () -> Date) {
        self.telemetry = telemetry
        self.now = now
    }

    var currentRoute: String? { state.withLock { $0.last } }

    func appeared(_ route: String) {
        let time = now()
        let referrer: String? = state.withLock { state in
            guard state.visible[route] == nil else { return nil }
            let previous = state.last == route ? nil : state.last
            state.last = route
            state.visible[route] = .some(time)
            return previous
        }
        telemetry.track(.screenView(route: route, referrer: referrer))
    }

    func disappeared(_ route: String) {
        let time = now()
        let started: Date? = state.withLock { state in
            guard let entry = state.visible.removeValue(forKey: route) else { return nil }
            return entry
        }
        if let started { emitTime(route, from: started, to: time) }
    }

    func didEnterBackground() {
        let time = now()
        let running: [(String, Date)] = state.withLock { state in
            var out: [(String, Date)] = []
            for (route, start) in state.visible {
                if let start { out.append((route, start)) }
                state.visible[route] = .some(nil)
            }
            return out
        }
        for (route, start) in running { emitTime(route, from: start, to: time) }
    }

    func didBecomeActive() {
        let time = now()
        state.withLock { state in
            for route in state.visible.keys { state.visible[route] = .some(time) }
        }
    }

    private func emitTime(_ route: String, from start: Date, to end: Date) {
        let ms = Int(max(0, end.timeIntervalSince(start)) * 1000)
        telemetry.track(.screenTime(route: route, ms: ms))
    }
}

private struct TelemetryScreenModifier: ViewModifier {
    let template: String
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { ScreenTracker.shared.appeared(template) }
            .onDisappear { ScreenTracker.shared.disappeared(template) }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: ScreenTracker.shared.didEnterBackground()
                case .active: ScreenTracker.shared.didBecomeActive()
                default: break
                }
            }
    }
}

private struct TelemetryToggleModifier: ViewModifier {
    let tid: String
    let value: Bool

    func body(content: Content) -> some View {
        content.onChange(of: value) { _, newValue in
            let route = ScreenTracker.shared.currentRoute ?? "/other"
            Telemetry.shared.track(.uiToggle(tid: tid, route: route, on: newValue))
        }
    }
}

extension View {
    /// `screen_view` on appear (referrer = the previous route), `screen_time` on disappear and on background.
    /// `template` is a route template such as `/share/:token`, never a raw path.
    public func telemetryScreen(_ template: String) -> some View {
        modifier(TelemetryScreenModifier(template: template))
    }

    /// `ui_toggle` whenever `value` changes, on the current screen.
    public func telemetryToggle(tid: String, value: Bool) -> some View {
        modifier(TelemetryToggleModifier(tid: tid, value: value))
    }
}
