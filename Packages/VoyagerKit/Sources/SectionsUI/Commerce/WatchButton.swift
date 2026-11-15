import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// "Watch price": hands the spec to the host (`ctx.watch`) and emits `alert_event(watch_tap, kind)`. The caller
/// decides whether to show it (never for an estimate: nothing live to watch).
struct WatchButton: View {
    let kind: WatchKind
    let spec: JSONValue
    let tid: String
    let title: String
    let accessibilityName: String
    let ctx: SectionContext

    private var request: WatchRequest {
        switch kind {
        case .flight: .fare(spec)
        case .hotel: .hotel(spec)
        case .activity: .activity(spec)
        case .trip: .trip(spec)
        }
    }

    /// Without live prices the server cannot start a watch, so the button is not shown (Alerts 2.0).
    private var state: QuickWatchState { ctx.watchState?(request) ?? .idle }

    var body: some View {
        if let watch = ctx.watch, !state.isHidden {
            let current = state
            VButton(label(for: current), tid: tid, role: current.isWatching ? .secondary : .tonal, systemImage: icon(for: current)) {
                Telemetry.shared.track(.alertEvent(action: "watch_tap", kind: kind.rawValue))
                watch(request)
            }
            .accessibilityLabel(accessibility(for: current))
            .accessibilityValue(current.isPending ? L10n.text(K.quickWatch.prices.pending) : "")
        }
    }

    private func label(for state: QuickWatchState) -> String {
        switch state {
        case .existing: L10n.text(K.quickWatch.label.already)
        case .pending: L10n.text(K.quickWatch.label.watching)
        default: title
        }
    }

    private func icon(for state: QuickWatchState) -> String {
        switch state {
        case .existing: "bell.fill"
        case .pending: "checkmark"
        default: "bell"
        }
    }

    private func accessibility(for state: QuickWatchState) -> String {
        guard state.isWatching else { return accessibilityName }
        let name = spec["name"].string
            ?? [spec["origin"].string, spec["destination"].string].compactMap { $0 }.joined(separator: " → ")
        return L10n.text(K.quickWatch.aria.already, ["title": name])
    }
}

/// The row's three actions: add to / remove from My Plan, Book (the provider page in Safari), Watch.
struct RowActions: View {
    let tidPrefix: String
    let selected: Bool
    let toggle: () -> Void
    let bookURL: URL?
    let section: String
    /// A ready watch button, or nil (estimates, past dates, multi-city).
    var watch: WatchButton?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { buttons }
            VStack(alignment: .leading, spacing: Spacing.sm) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        VButton(
            L10n.text(selected ? K.results.plan.addedToPlan : K.results.plan.addToPlan),
            tid: "\(tidPrefix).add", role: selected ? .primary : .secondary,
            systemImage: selected ? "checkmark" : "plus", action: toggle
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
        if let bookURL {
            BookingLink(url: bookURL, section: section, tid: "\(tidPrefix).book")
        }
        if let watch { watch }
    }
}

/// A small tinted capsule: source, tag, tier.
struct CommerceTag: View {
    let text: String
    var family: Family = .gray

    var body: some View {
        Text(verbatim: text)
            .font(VFont.body(.caption, weight: .medium))
            .foregroundStyle(Palette.color(family, .s700))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Palette.color(family, .s100), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}
