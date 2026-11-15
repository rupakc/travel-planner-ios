import Foundation
import L10n
import Networking
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// Settings > Alert preferences (`GET|PUT /alerts/preferences`): the weekly digest, instant pushes, quiet hours, the
/// per-kind daily caps and the grouping window. Every change is saved at once as a patch of the changed keys. A refused
/// save (`422 alert_prefs_invalid`) or a failed one puts the previous setting back, so the screen never shows a value
/// the server does not have. The account time zone is the server's and is shown read-only.
@MainActor @Observable
public final class AlertPrefsModel {
    public enum Phase: Equatable, Sendable {
        case loading, loaded
        /// The route is off (an older backend or `alerts_api` < 2): nothing is shown.
        case unavailable
        case failed
    }

    public enum SaveFailure: Equatable, Sendable {
        /// `422 alert_prefs_invalid`: the previous setting was kept.
        case invalid
        case failed
    }

    static let capRange = 1...10
    static let groupRange = 0...120
    static let groupStep = 5

    public private(set) var phase: Phase = .loading
    /// What the screen shows: the last server answer with the edits in flight applied.
    public private(set) var prefs = AlertPrefs()
    public private(set) var saveFailure: SaveFailure?
    public private(set) var loadError: (any ErrorPresentable)?

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    /// The last value the server confirmed (what a failed save returns to).
    @ObservationIgnored private var confirmed = AlertPrefs()
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var queued: AlertPrefsPatch?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(env: AppEnvironment, track: (@MainActor (TelemetryEvent) -> Void)? = nil) {
        self.env = env
        self.track = track ?? { [unowned env] in env.telemetry.track($0) }
    }

    // MARK: Derived

    /// The digest push has no effect without the weekly digest, so its switch is off-limits until that is on.
    public var canEditDigestPush: Bool { prefs.digestWeekly }

    /// The server applies quiet hours in the account time zone; without one they are not applied.
    public var quietHoursNeedTimezone: Bool { prefs.quietHours.enabled && prefs.timezone == nil }

    // MARK: Load

    /// First load and every re-appearance (quiet hours are shared with the notification settings, which save them
    /// through their own route).
    public func load() async {
        guard env.alertsV2.isAvailable(.stored) else {
            phase = .unavailable
            return
        }
        if phase != .loaded { phase = .loading }
        loadError = nil
        do {
            let fetched = try await env.alertsV2.prefs()
            guard !inFlight else { return }
            confirmed = fetched
            prefs = fetched
            saveFailure = nil
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            if phase == .loaded { return }  // a failed refetch keeps what is shown
            if error is AlertsV2Service.Unavailable {
                phase = .unavailable
            } else {
                loadError = error as? any ErrorPresentable
                phase = .failed
            }
        }
    }

    // MARK: Edits

    public func setDigestWeekly(_ on: Bool) {
        guard prefs.digestWeekly != on else { return }
        prefs.digestWeekly = on
        edit(.digest, AlertPrefsPatch(digestWeekly: on))
    }

    public func setDigestPush(_ on: Bool) {
        guard canEditDigestPush, prefs.digestPush != on else { return }
        prefs.digestPush = on
        edit(.digest, AlertPrefsPatch(digestPush: on))
    }

    public func setDigestDay(_ day: Int) {
        guard (1...7).contains(day), prefs.digestDay != day else { return }
        prefs.digestDay = day
        edit(.digest, AlertPrefsPatch(digestDay: day))
    }

    public func setInstantTargetsOnly(_ on: Bool) {
        let mode: InstantMode = on ? .targetsOnly : .all
        guard prefs.instant != mode else { return }
        prefs.instant = mode
        edit(.instant, AlertPrefsPatch(instant: mode))
    }

    public func setQuietEnabled(_ on: Bool) {
        guard prefs.quietHours.enabled != on else { return }
        prefs.quietHours.enabled = on
        edit(.quietHours, AlertPrefsPatch(quietHours: prefs.quietHours))
    }

    public func setQuietTimes(start: String? = nil, end: String? = nil) {
        var quiet = prefs.quietHours
        if let start { quiet.start = start }
        if let end { quiet.end = end }
        guard quiet != prefs.quietHours else { return }
        prefs.quietHours = quiet
        edit(.quietHours, AlertPrefsPatch(quietHours: quiet))
    }

    public func setCap(_ kind: WatchKind, _ value: Int) {
        let clamped = min(max(value, Self.capRange.lowerBound), Self.capRange.upperBound)
        guard prefs.dailyCap[kind] != clamped else { return }
        prefs.dailyCap[kind] = clamped
        edit(.cap, AlertPrefsPatch(dailyCap: prefs.dailyCap))
    }

    public func setGroupWindow(_ minutes: Int) {
        let clamped = min(max(minutes, Self.groupRange.lowerBound), Self.groupRange.upperBound)
        guard prefs.groupWindowMin != clamped else { return }
        prefs.groupWindowMin = clamped
        edit(.group, AlertPrefsPatch(groupWindowMin: clamped))
    }

    // MARK: Saving

    enum Field: String { case digest, quietHours = "quiet_hours", instant, cap, group }

    private func edit(_ field: Field, _ patch: AlertPrefsPatch) {
        track(.alertPrefsChange(field: field.rawValue))
        saveFailure = nil
        if inFlight {
            queued = queued.map { $0.merging(patch) } ?? patch
            return
        }
        inFlight = true
        saveTask = Task { await flush(patch) }
    }

    /// Returns when every save started so far finished (tests).
    public func waitForSaves() async { await saveTask?.value }

    private func flush(_ first: AlertPrefsPatch) async {
        var patch = first
        while true {
            do {
                let answer = try await env.alertsV2.updatePrefs(patch)
                confirmed = answer
                if let next = queued {
                    // Keep the edits still in flight on top of the server's answer.
                    queued = nil
                    prefs = answer
                    prefs.apply(next)
                    patch = next
                    continue
                }
                prefs = answer
            } catch {
                queued = nil
                prefs = confirmed
                saveFailure = Self.failure(error)
            }
            inFlight = false
            return
        }
    }

    static func failure(_ error: Error) -> SaveFailure {
        if let api = error as? APIError, errorCode(api) == "alert_prefs_invalid" { return .invalid }
        return .failed
    }

    var saveFailureMessage: String? {
        switch saveFailure {
        case .invalid: L10n.text(K.alertPrefs.error.invalid)
        case .failed: L10n.text(K.alertPrefs.error.save)
        case nil: nil
        }
    }

    /// Shows the screen without a request (previews and snapshots).
    func show(_ prefs: AlertPrefs) {
        self.prefs = prefs
        confirmed = prefs
        phase = .loaded
    }
}

extension AlertPrefsPatch {
    /// This patch with `newer`'s keys on top.
    func merging(_ newer: AlertPrefsPatch) -> AlertPrefsPatch {
        AlertPrefsPatch(
            digestWeekly: newer.digestWeekly ?? digestWeekly, digestPush: newer.digestPush ?? digestPush,
            digestDay: newer.digestDay ?? digestDay, instant: newer.instant ?? instant,
            quietHours: newer.quietHours ?? quietHours, dailyCap: newer.dailyCap ?? dailyCap,
            groupWindowMin: newer.groupWindowMin ?? groupWindowMin)
    }
}

extension AlertPrefs {
    mutating func apply(_ patch: AlertPrefsPatch) {
        if let value = patch.digestWeekly { digestWeekly = value }
        if let value = patch.digestPush { digestPush = value }
        if let value = patch.digestDay { digestDay = value }
        if let value = patch.instant { instant = value }
        if let value = patch.quietHours { quietHours = value }
        if let value = patch.dailyCap { dailyCap = value }
        if let value = patch.groupWindowMin { groupWindowMin = value }
    }
}
