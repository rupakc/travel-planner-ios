import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The "Want us to watch these prices?" sheet of a saved plan (`GET /alerts/suggestions?plan_id=`). Needs live prices
/// (plan ruling R3); without them the sheet has nothing to show and no route is called. "Watch N" starts one pending
/// watch per ticked row, one after the other, stopping at the shared limit.
@MainActor @Observable
public final class SuggestionsModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case loaded
        /// Nothing to offer: live prices are off, the route is missing, or there are no suggestions.
        case hidden
        case failed(String)
    }

    public enum RowStatus: Equatable, Sendable {
        case idle
        case running
        case done
        case already
        case failed(String)
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: Int
        public let suggestion: WatchSuggestion
        public var status: RowStatus
        public var selected: Bool
    }

    public private(set) var phase: Phase = .loading
    public private(set) var rows: [Row] = []
    public private(set) var isWatching = false

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let planID: Int
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var shownTracked = false
    @ObservationIgnored private var accepted = false

    public init(env: AppEnvironment, planID: Int, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.planID = planID
        self.track = track ?? { [unowned env] in env.telemetry.track($0) }
    }

    /// Whether the sheet may be offered at all (no request is made when it may not).
    public var isAvailable: Bool { env.alertsV2.isAvailable(.quickWatch) }

    public var selectedCount: Int { rows.filter { $0.selected && $0.status == .idle }.count }
    /// Something was tried and nothing is left to try (a limit stopped the rest): the watch button has no job.
    public var nothingLeftToWatch: Bool { selectedCount == 0 && rows.contains { $0.status != .idle } }
    public var canWatch: Bool { !isWatching && selectedCount > 0 }
    /// Every ticked row has been tried.
    public var isFinished: Bool { !rows.isEmpty && rows.allSatisfy { $0.status != .idle && $0.status != .running } }

    public func load() async {
        guard isAvailable else {
            phase = .hidden
            return
        }
        if rows.isEmpty { phase = .loading }
        do {
            let answer = try await env.alertsV2.suggestions(planID: planID)
            guard answer.livePrices, !answer.suggestions.isEmpty else {
                phase = .hidden
                return
            }
            rows = answer.suggestions.enumerated().map { index, suggestion in
                Row(
                    id: index, suggestion: suggestion, status: suggestion.alreadyWatching ? .already : .idle,
                    selected: !suggestion.alreadyWatching)
            }
            phase = .loaded
            if !shownTracked {
                shownTracked = true
                track(.alertSuggest(action: "shown", count: rows.count))
            }
        } catch is CancellationError {
            return
        } catch {
            if error is AlertsV2Service.Unavailable {
                phase = .hidden
            } else if rows.isEmpty {
                phase = .failed(Self.message(error))
            }
        }
    }

    public func toggle(_ id: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows[index].status == .idle, !isWatching else { return }
        rows[index].selected.toggle()
    }

    /// Watches every ticked row.
    public func watchSelected() async {
        guard canWatch else { return }
        isWatching = true
        defer { isWatching = false }
        if !accepted {
            accepted = true
            track(.alertSuggest(action: "accepted", count: selectedCount))
        }
        for index in rows.indices where rows[index].selected && rows[index].status == .idle {
            rows[index].status = .running
            let suggestion = rows[index].suggestion
            let request = QuickWatchRequest(
                kind: suggestion.kind, title: suggestion.title, subtitle: suggestion.subtitle, spec: suggestion.spec,
                planId: planID, surface: .suggest)
            do {
                let result = try await env.alertsV2.quickWatch(request)
                rows[index].status = result.existing ? .already : .done
                track(
                    .alertQuickWatch(
                        kind: suggestion.kind.rawValue, action: result.existing ? "exists" : "add", surface: "suggest"))
            } catch {
                let code = (error as? APIError).flatMap(errorCode)
                rows[index].status = .failed(Self.message(error))
                track(.alertQuickWatch(kind: suggestion.kind.rawValue, action: "blocked", surface: "suggest"))
                if code == "watch_limit" || code == "live_prices_off" { return }  // the rest would fail the same way
            }
        }
    }

    /// The sheet was closed: `alert_suggest dismissed` unless the user started watching.
    public func dismiss() {
        guard shownTracked, !accepted else { return }
        accepted = true  // reported once
        track(.alertSuggest(action: "dismissed", count: rows.count))
    }

    static func message(_ error: Error) -> String {
        switch (error as? APIError).flatMap(errorCode) ?? "" {
        case "watch_limit": L10n.text(K.watchSuggest.error.watch_limit)
        case "live_prices_off": L10n.text(K.watchSuggest.error.live_prices_off)
        case "spec_invalid": L10n.text(K.watchSuggest.error.spec_invalid)
        default: L10n.text(K.watchSuggest.error.generic)
        }
    }

    /// The row's "why" line; an unknown reason has none.
    static func reasonText(_ reason: SuggestionReason) -> String? {
        switch reason {
        case .selectedInPlan: L10n.text(K.watchSuggest.reason.selected_in_plan)
        case .tripTotal: L10n.text(K.watchSuggest.reason.trip_total)
        case .departureSoon: L10n.text(K.watchSuggest.reason.departure_soon)
        case .unknown: nil
        }
    }

    /// Shows rows without a request (previews and snapshots).
    func show(_ rows: [Row]) {
        self.rows = rows
        phase = .loaded
    }
}

extension SuggestionsModel.Row {
    init(_ suggestion: WatchSuggestion, id: Int, status: SuggestionsModel.RowStatus = .idle, selected: Bool = true) {
        self.init(id: id, suggestion: suggestion, status: status, selected: selected)
    }
}
