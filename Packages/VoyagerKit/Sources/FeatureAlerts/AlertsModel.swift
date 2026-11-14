import AuthCore
import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The kind filter above the watch list.
public enum AlertsFilter: String, CaseIterable, Sendable, Identifiable {
    case all, flight, hotel, activity, trip

    public var id: String { rawValue }
    public var kind: WatchKind? { WatchKind(rawValue: rawValue) }

    init(_ kind: WatchKind?) { self = kind.flatMap { AlertsFilter(rawValue: $0.rawValue) } ?? .all }
}

/// What the edit panel saves.
public struct WatchEdit: Equatable, Sendable {
    public var alertMode: String
    public var target: Double?
    public var flexible: Bool
    public var emailEnabled: Bool

    public init(alertMode: String, target: Double?, flexible: Bool, emailEnabled: Bool) {
        self.alertMode = alertMode
        self.target = target
        self.flexible = flexible
        self.emailEnabled = emailEnabled
    }
}

/// The live-web-search result for one watch, shown in `LiveCheckSheet`. Held in memory only; never stored.
public struct LiveCheckState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case searching
        case result(LiveCheckResult)
        case failed(String)
    }

    public var row: WatchRow
    public var phase: Phase
}

/// The Alerts tab: the caller's fare watches and price watches in one list with a kind filter, per-watch
/// actions (pause / resume, edit, delete, check now, live web search) and a focus (from a notification or deep
/// link) that selects the watch's kind and scrolls to it.
@MainActor @Observable
public final class AlertsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public enum Busy: Equatable, Sendable { case check, save, delete, status }

    public private(set) var phase: Phase = .loading
    public private(set) var rows: [WatchRow] = []
    /// A list that failed to load while the other one did.
    public private(set) var partialNotes: [String] = []
    public var filter: AlertsFilter
    public private(set) var focusedID: String?
    public private(set) var busy: [String: Busy] = [:]
    public var toast: ToastMessage?
    public var editing: WatchRow?
    public var liveCheck: LiveCheckState?
    /// Unread notifications, for the bell. The bell is hidden when the server has no notifications API.
    public private(set) var unread = 0
    public private(set) var notifications404 = false

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let focusKind: WatchKind?
    @ObservationIgnored private let focusWatch: Int?
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var liveRun = 0

    public init(
        env: AppEnvironment, kind: WatchKind? = nil, watchID: Int? = nil,
        track: (@MainActor (TelemetryEvent) -> Void)? = nil, now: (@MainActor () -> Date)? = nil
    ) {
        self.env = env
        focusKind = kind
        focusWatch = watchID
        filter = AlertsFilter(kind)
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
        self.now = now ?? { Date() }
    }

    // MARK: - Reading

    /// `features.live_prices` from `/api/config`; true when unknown (older backend: act as before).
    public var livePrices: Bool { env.clientConfig?.features["live_prices"]?.bool ?? true }

    public func count(_ filter: AlertsFilter) -> Int {
        guard let kind = filter.kind else { return rows.count }
        return rows.filter { $0.kind == kind }.count
    }

    /// "Now" for relative times (injectable for tests).
    public var currentDate: Date { now() }

    public var filtered: [WatchRow] {
        guard let kind = filter.kind else { return rows }
        return rows.filter { $0.kind == kind }
    }

    public var activeRows: [WatchRow] { filtered.filter { !$0.isPast } }
    public var pastRows: [WatchRow] { filtered.filter(\.isPast) }

    /// "Showing 3 flight watches", pluralised.
    public func statusText(_ filter: AlertsFilter) -> String {
        let key: LKey
        switch filter {
        case .all: key = K.alerts.tabs.status.all
        case .flight: key = K.alerts.tabs.status.flight
        case .hotel: key = K.alerts.tabs.status.hotel
        case .activity: key = K.alerts.tabs.status.activity
        case .trip: key = K.alerts.tabs.status.trip
        }
        return L10n.text(key, count: count(filter))
    }

    public func tabTitle(_ filter: AlertsFilter) -> String {
        switch filter {
        case .all: L10n.text(K.alerts.tabs.all)
        case .flight: L10n.text(K.alerts.tabs.flight)
        case .hotel: L10n.text(K.alerts.tabs.hotel)
        case .activity: L10n.text(K.alerts.tabs.activity)
        case .trip: L10n.text(K.alerts.tabs.trip)
        }
    }

    public func emptyText(_ filter: AlertsFilter) -> String {
        switch filter {
        case .all: L10n.text(livePrices ? K.alerts.page.emptyOn : K.alerts.page.emptyOff)
        case .flight: L10n.text(K.alerts.tabs.empty.flight)
        case .hotel: L10n.text(K.alerts.tabs.empty.hotel)
        case .activity: L10n.text(K.alerts.tabs.empty.activity)
        case .trip: L10n.text(K.alerts.tabs.empty.trip)
        }
    }

    // MARK: - Loading

    public func load() async {
        if rows.isEmpty { phase = .loading }
        let repo = env.repos.watches
        async let fares = Self.attempt { try await repo.fareWatches() }
        async let prices = Self.attempt { try await repo.priceWatches(kind: nil) }
        let (fareResult, priceResult) = await (fares, prices)
        var notes: [String] = []
        var all: [WatchRow] = []
        var failure: (any Error)?
        switch fareResult {
        case .success(let watches): all += watches.map(WatchRow.init)
        case .failure(let error):
            failure = error
            notes.append(L10n.text(K.alerts.page.loadFailed))
        }
        switch priceResult {
        case .success(let watches): all += watches.map(WatchRow.init)
        case .failure(let error):
            failure = failure ?? error
            notes.append(L10n.text(K.alerts.page.priceLoadFailed))
        }
        if case .failure = fareResult, case .failure = priceResult {
            phase = .failed(ErrorCopy.message(kind: Self.kind(failure), detail: (failure as? APIError)?.userFacingDetail))
            return
        }
        rows = all
        partialNotes = notes
        phase = .loaded
        applyFocus()
    }

    private nonisolated static func attempt<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> Result<T, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private static func kind(_ error: (any Error)?) -> ErrorPresentationKind {
        (error as? APIError)?.presentationKind ?? .other
    }

    /// Selects the focused watch's kind tab and marks it for the view to scroll to.
    private func applyFocus() {
        guard let watchID = focusWatch else { return }
        let match = rows.first { $0.watchID == watchID && (focusKind == nil || $0.kind == focusKind) }
        guard let match else { return }
        focusedID = match.id
        filter = AlertsFilter(match.kind)
    }

    /// Reads the unread count; a 404 (older backend) hides the inbox entry.
    public func loadInbox() async {
        do {
            unread = max(try await env.repos.notifications.unreadCount(), 0)
            notifications404 = false
        } catch APIError.notFound {
            notifications404 = true
        } catch {
            // A failed count keeps the last one.
        }
    }

    public func openInbox() {
        env.router.open(.notifications)
    }

    /// Whether the account has an email address (the per-watch email switch needs one).
    public var hasEmail: Bool { !(env.auth.session?.user.email ?? "").isEmpty }

    // MARK: - Actions

    public func togglePause(_ row: WatchRow) async {
        let resume = row.isPaused || row.isErrored
        await patch(row, WatchPatch(status: resume ? "active" : "paused"), busy: .status) { [self] _ in
            track(.alertEvent(action: resume ? "watch_resume" : "watch_pause", kind: row.kind.rawValue))
            toast = ToastMessage(
                resume
                    ? L10n.text(K.alerts.checks.resumed)
                    : L10n.text(row.kind == .flight ? K.alerts.checks.pausedFare : K.alerts.checks.pausedPrice))
        }
    }

    public func save(_ row: WatchRow, _ edit: WatchEdit) async {
        var change = WatchPatch(alertMode: edit.alertMode, emailEnabled: edit.emailEnabled)
        if edit.alertMode == "below_target" { change.targetPrice = edit.target }
        if row.supportsFlexible { change.flexibleDays = edit.flexible ? 3 : 0 }
        await patch(row, change, busy: .save) { [self] _ in
            editing = nil
            track(.alertEvent(action: "watch_edit", kind: row.kind.rawValue))
            toast = ToastMessage(L10n.text(K.alerts.checks.saved))
        }
    }

    public func setEmail(_ row: WatchRow, enabled: Bool) async {
        await patch(row, WatchPatch(emailEnabled: enabled), busy: .save) { [self] _ in
            track(.alertEvent(action: "watch_email", kind: row.kind.rawValue))
        }
    }

    private func patch(
        _ row: WatchRow, _ change: WatchPatch, busy kind: Busy, then done: @MainActor (WatchRow) -> Void
    ) async {
        guard busy[row.id] == nil else { return }
        busy[row.id] = kind
        defer { busy[row.id] = nil }
        do {
            let item = try await env.repos.watches.patch(kind: row.kind, id: row.watchID, change)
            let updated = replace(row, with: item)
            done(updated)
            await env.watchesChanged()
        } catch {
            toast = ToastMessage(Self.failureText(error, fallback: L10n.text(K.alerts.checks.saveFailed)))
        }
    }

    public func delete(_ row: WatchRow) async {
        guard busy[row.id] == nil else { return }
        busy[row.id] = .delete
        defer { busy[row.id] = nil }
        do {
            try await env.repos.watches.delete(kind: row.kind, id: row.watchID)
            rows.removeAll { $0.id == row.id }
            if focusedID == row.id { focusedID = nil }
            track(.alertEvent(action: "watch_delete", kind: row.kind.rawValue))
            await env.watchesChanged()
        } catch {
            toast = ToastMessage(Self.failureText(error, fallback: L10n.text(K.alerts.checks.deleteFailed)))
        }
    }

    /// "Check now": one live check; the toast reads out what happened.
    public func check(_ row: WatchRow) async {
        guard busy[row.id] == nil else { return }
        busy[row.id] = .check
        defer { busy[row.id] = nil }
        do {
            let item = try await env.repos.watches.check(kind: row.kind, id: row.watchID)
            let updated = replace(row, with: item)
            track(.alertEvent(action: "watch_check", kind: row.kind.rawValue))
            toast = ToastMessage(Self.checkText(item, row: updated))
        } catch {
            toast = ToastMessage(Self.failureText(error, fallback: L10n.text(K.alerts.checks.checkFailed)))
        }
    }

    @discardableResult
    private func replace(_ row: WatchRow, with item: WatchItem) -> WatchRow {
        var updated = WatchRow(item)
        if updated.history.isEmpty { updated.history = row.history }
        if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = updated }
        return updated
    }

    static func failureText(_ error: any Error, fallback: String) -> String {
        if let detail = (error as? APIError)?.userFacingDetail, !detail.isEmpty { return detail }
        return fallback
    }

    /// The outcome of "Check now", from `check_status` (fare and price keep their own copy).
    static func checkText(_ item: WatchItem, row: WatchRow) -> String {
        switch item {
        case .fare(let watch):
            switch watch.checkStatus {
            case "checked":
                guard let price = watch.lastPrice else { return L10n.text(K.alerts.checks.noFares) }
                return L10n.text(K.alerts.checks.justNow, ["price": Fmt.currency(price, code: "USD")])
            case "failed": return L10n.text(K.alerts.checks.failed)
            case "errored": return L10n.text(K.alerts.checks.errored)
            case "postponed": return L10n.text(K.alerts.checks.postponed)
            case "expired": return L10n.text(K.alerts.checks.expired)
            case "deleted": return L10n.text(K.alerts.checks.deleted)
            default: return L10n.text(K.alerts.checks.default)
            }
        case .price(let watch):
            switch watch.checkStatus {
            case "checked": return L10n.text(K.alerts.checksPrice.checked)
            case "failed": return L10n.text(K.alerts.checksPrice.failed)
            case "errored": return L10n.text(K.alerts.checksPrice.errored)
            case "postponed": return L10n.text(K.alerts.checksPrice.postponed)
            case "expired": return L10n.text(K.alerts.checksPrice.expired)
            case "unavailable": return L10n.text(K.alerts.checksPrice.unavailable)
            default: return L10n.text(K.alerts.checksPrice.default)
            }
        }
    }

    // MARK: - Live web search

    /// "Search the web now": the result goes to `liveCheck` for the sheet and nowhere else.
    public func startLiveCheck(_ row: WatchRow) async {
        liveRun += 1
        let run = liveRun
        liveCheck = LiveCheckState(row: row, phase: .searching)
        track(.alertEvent(action: "live_check", kind: row.kind.rawValue))
        do {
            let result = try await env.repos.watches.liveCheck(LiveCheckRequest(kind: row.kind, watchId: row.watchID))
            guard run == liveRun, liveCheck?.row.id == row.id else { return }
            liveCheck = LiveCheckState(row: row, phase: .result(result))
        } catch {
            guard run == liveRun, liveCheck?.row.id == row.id else { return }
            liveCheck = LiveCheckState(
                row: row,
                phase: .failed(Self.failureText(error, fallback: L10n.text(K.alerts.checks.checkFailed))))
        }
    }

    public func dismissLiveCheck() {
        liveRun += 1
        liveCheck = nil
    }

    // MARK: - Test seams

    func show(rows: [WatchRow], phase: Phase = .loaded) {
        self.rows = rows
        self.phase = phase
    }
}
