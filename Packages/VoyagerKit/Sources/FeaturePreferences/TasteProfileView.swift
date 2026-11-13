import DesignSystem
import L10n
import Observation
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The learned Taste Graph (`GET /api/taste-profile`) and its reset (`DELETE`, after a confirmation).
@MainActor @Observable
final class TasteModel {
    enum Phase { case loading, loaded, failed }

    nonisolated static let signalOrder = [
        "activity_category", "event_category", "hotel_tier", "flight_style", "interest", "destination", "pace",
    ]
    nonisolated static let maxEntries = 4

    private let env: AppEnvironment
    @ObservationIgnored private let track: (TelemetryEvent) -> Void
    private(set) var phase = Phase.loading
    private(set) var profile = TasteProfile()
    private(set) var resetting = false
    private(set) var resetFailed = false
    var confirmingReset = false

    init(env: AppEnvironment, track: ((TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.track = track ?? { env.telemetry.track($0) }
    }

    var hasSignals: Bool { (profile.totalSignals ?? 0) > 0 }

    /// Signal types in a stable order (known ones first), each with its first entries that carry a value.
    var rows: [TasteRow] {
        let signals = profile.signals ?? [:]
        let known = Self.signalOrder.filter { signals[$0] != nil }
        let others = signals.keys.filter { !Self.signalOrder.contains($0) }.sorted()
        return (known + others).compactMap { type -> TasteRow? in
            let entries = (signals[type] ?? []).filter { ($0.value ?? "").isEmpty == false }.prefix(Self.maxEntries)
            return entries.isEmpty ? nil : TasteRow(type: type, entries: Array(entries))
        }
    }

    func load() async {
        phase = .loading
        do {
            profile = try await env.repos.preferences.taste()
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    /// Step one: ask. Nothing is deleted until `confirmReset`.
    func requestReset() {
        guard hasSignals, !resetting else { return }
        confirmingReset = true
    }

    func cancelReset() { confirmingReset = false }

    func confirmReset() async {
        confirmingReset = false
        guard hasSignals, !resetting else { return }
        resetting = true
        resetFailed = false
        do {
            try await env.repos.preferences.resetTaste()
            track(.featureUsed(feature: "taste_reset", page: "preferences"))
            resetting = false
            await load()
        } catch {
            resetFailed = true
            resetting = false
        }
    }
}

struct TasteRow: Identifiable {
    let type: String
    let entries: [TasteSignal]
    var id: String { type }
}

/// The card body, shared by the Preferences screen and the standalone screen.
struct TasteProfileCard: View {
    @Bindable var model: TasteModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(verbatim: L10n.text(K.account.prefs.taste.title))
                    .font(VFont.display(.headline)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.sm)
                if model.hasSignals {
                    Button { model.requestReset() } label: {
                        Label(L10n.text(K.account.prefs.taste.reset), systemImage: "trash")
                            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.resetting)
                    .accessibilityIdentifier("prefs.tasteReset")
                }
            }
            Text(verbatim: L10n.text(K.account.prefs.taste.heading))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            content
        }
        .confirmationDialog(
            L10n.text(K.account.prefs.taste.confirmReset), isPresented: $model.confirmingReset, titleVisibility: .visible
        ) {
            Button(L10n.text(K.account.prefs.taste.reset), role: .destructive) { Task { await model.confirmReset() } }
                .accessibilityIdentifier("prefs.tasteResetConfirm")
            Button(L10n.text(K.account.admin.common.cancel), role: .cancel) { model.cancelReset() }
                .accessibilityIdentifier("prefs.tasteResetCancel")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("prefs.tasteLoading")
        case .failed:
            Text(verbatim: L10n.text(K.account.prefs.taste.loadFailed))
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
        case .loaded:
            if model.hasSignals {
                let built = L10n.text(K.account.prefs.taste.built, count: model.profile.totalSignals ?? 0)
                Text(verbatim: "\(built) \(L10n.text(K.account.prefs.taste.personalised))")
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(model.rows) { row in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: Self.title(row.type))
                            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        ChipGrid(items: row.entries, spacing: Spacing.xs) { entry in
                            Text(verbatim: "\(entry.value ?? "") ×\(entry.count ?? 0)")
                                .font(VFont.body(.caption)).lineLimit(2)
                                .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                                .background(SemanticColor.border, in: Capsule())
                                .foregroundStyle(SemanticColor.text)
                        }
                    }
                }
            } else {
                Text(verbatim: L10n.text(K.account.prefs.taste.empty))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.resetFailed {
                Text(verbatim: L10n.text(K.account.prefs.taste.resetFailed))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.destructive)
            }
        }
    }

    static func title(_ type: String) -> String {
        switch type {
        case "activity_category": L10n.text(K.account.prefs.signal.activity_category)
        case "event_category": L10n.text(K.account.prefs.signal.event_category)
        case "hotel_tier": L10n.text(K.account.prefs.signal.hotel_tier)
        case "flight_style": L10n.text(K.account.prefs.signal.flight_style)
        case "interest": L10n.text(K.account.prefs.signal.interest)
        case "destination": L10n.text(K.account.prefs.signal.destination)
        case "pace": L10n.text(K.account.prefs.signal.pace)
        default: type
        }
    }
}

/// Standalone Taste profile screen (`Route.tasteProfile`).
public struct TasteProfileView: View {
    @State private var model: TasteModel

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: TasteModel(env: env))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VCard { TasteProfileCard(model: model) }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .navigationTitle(L10n.text(K.account.prefs.taste.title))
        .task { if model.phase == .loading { await model.load() } }
        .telemetryScreen(TelemetryRouteName.template(for: .tasteProfile))
        .accessibilityIdentifier("taste.root")
    }
}
