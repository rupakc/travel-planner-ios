import Foundation
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// You > Notifications (plan ruling R7): the seven category switches, quiet hours, the daily cap, the read-only account
/// time zone and the push status, over `GET|PUT /api/notification-settings`. Every change is saved at once. A failed save
/// (the server's `422 notification_settings_invalid` included) undoes the change and shows the web's "undone" message,
/// so the screen never shows a value the server does not have.
@MainActor @Observable
final class NotificationSettingsModel {
    enum Phase: Equatable { case loading, loaded, failed, unavailable }

    private let service: NotificationSettingsService
    private let permissionProvider: any NotificationPermissionProviding
    @ObservationIgnored private let track: (TelemetryEvent) -> Void
    @ObservationIgnored private let gameVisibility: @MainActor () -> any GameVisibility
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var queued: NotificationSettingsPatch?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    private(set) var phase = Phase.loading
    private(set) var loadError: (any ErrorPresentable)?
    /// What the screen shows: the last server answer with the edits in flight applied.
    private(set) var settings = NotificationSettings()
    /// True after a save failed (until the next change or load).
    private(set) var saveFailed = false
    private(set) var permission = NotificationPermissionState.unknown
    private(set) var viewTracked = false

    init(
        env: AppEnvironment, service: NotificationSettingsService? = nil,
        permission: any NotificationPermissionProviding = SystemNotificationPermission(),
        gameVisibility: (@MainActor () -> any GameVisibility)? = nil, track: ((TelemetryEvent) -> Void)? = nil
    ) {
        self.service = service ?? NotificationSettingsService(env: env)
        permissionProvider = permission
        self.gameVisibility = gameVisibility ?? { Self.defaultGameVisibility(env: env) }
        self.track = track ?? { env.telemetry.track($0) }
    }

    /// `features.game` from `/config`; the account's `hide_game` is not read by this screen yet, so it counts as unreadable
    /// and the quiz switch stays hidden (game wording is shown only when the setting is known to be off).
    static func defaultGameVisibility(env: AppEnvironment) -> any GameVisibility {
        StaticGameVisibility(gameFeature: RemoteFeatures(config: env.clientConfig).game, hideGameSetting: nil)
    }

    // MARK: - Rows

    /// The switches shown: every category, without `quiz` while game wording is hidden.
    var categories: [NotificationCategory] {
        let showsGame = gameVisibility().showsGame
        return NotificationCategory.allCases.filter { showsGame || !$0.isGameWording }
    }

    func isOn(_ category: NotificationCategory) -> Bool { settings.isEnabled(category) }

    /// The server cannot deliver to iOS yet (`push.apns` false): in-app and local notifications still work.
    var pushUnavailable: Bool { !settings.pushAPNS }
    var showsNoDevices: Bool { settings.pushAPNS && settings.devices == 0 }
    var hasTimezone: Bool { settings.timezone != nil }

    // MARK: - Load

    /// First load and every re-appearance: quiet hours are shared with the alert prefs, so the other screen's edit shows
    /// here after a refetch.
    func load() async {
        guard service.isAvailable else {
            phase = .unavailable
            return
        }
        await refreshPermission()
        if phase != .loaded { phase = .loading }
        loadError = nil
        do {
            settings = try await service.settings()
            saveFailed = false
            phase = .loaded
            if !viewTracked {
                viewTracked = true
                track(.notifSettingsView)
            }
        } catch {
            if phase == .loaded { return }  // a failed refetch keeps what is shown
            loadError = (error as? any ErrorPresentable) ?? SettingsLoadFailure()
            phase = (error is NotificationSettingsService.Unavailable) ? .unavailable : .failed
        }
    }

    func refreshPermission() async { permission = await permissionProvider.state() }

    /// The system prompt (only while the permission was never asked).
    func requestPermission() async {
        _ = await permissionProvider.request()
        await refreshPermission()
    }

    // MARK: - Edits

    func setCategory(_ category: NotificationCategory, on: Bool) {
        guard settings.isEnabled(category) != on else { return }
        settings.categories[category] = on
        track(.notifCategoryToggle(category: category.rawValue, on: on))
        send(NotificationSettingsPatch(categories: [category: on]))
    }

    func setQuietEnabled(_ enabled: Bool) {
        guard settings.quietHours.enabled != enabled else { return }
        settings.quietHours.enabled = enabled
        track(.notifQuietHoursChange(enabled: enabled))
        send(NotificationSettingsPatch(quietHours: settings.quietHours))
    }

    func setQuietTimes(start: String? = nil, end: String? = nil) {
        var quiet = settings.quietHours
        if let start { quiet.start = start }
        if let end { quiet.end = end }
        guard quiet != settings.quietHours else { return }
        settings.quietHours = quiet
        track(.notifQuietHoursChange(enabled: quiet.enabled))
        send(NotificationSettingsPatch(quietHours: quiet))
    }

    func setCap(_ cap: Int) {
        let clamped = min(max(cap, NotificationSettings.capRange.lowerBound), NotificationSettings.capRange.upperBound)
        guard clamped != settings.dailyCap else { return }
        settings.dailyCap = clamped
        track(.notifCapChange(cap: clamped))
        send(NotificationSettingsPatch(dailyCap: clamped))
    }

    // MARK: - Saving

    /// One save at a time: edits made while a save is in flight are merged and sent after it.
    private func send(_ patch: NotificationSettingsPatch) {
        saveFailed = false
        if inFlight {
            queued = queued?.merging(patch) ?? patch
            return
        }
        inFlight = true
        saveTask = Task { await flush(patch) }
    }

    /// Returns when every save started so far finished (tests).
    func waitForSaves() async { await saveTask?.value }

    private func flush(_ first: NotificationSettingsPatch) async {
        var patch = first
        while true {
            do {
                let confirmed = try await service.update(patch)
                if let next = queued {
                    // Keep the edits still in flight on top of the server's answer.
                    queued = nil
                    settings = confirmed
                    apply(next)
                    patch = next
                    continue
                }
                settings = confirmed
            } catch {
                queued = nil
                saveFailed = true
                await undo()
            }
            inFlight = false
            return
        }
    }

    private func apply(_ patch: NotificationSettingsPatch) {
        for (category, enabled) in patch.categories ?? [:] { settings.categories[category] = enabled }
        if let quiet = patch.quietHours { settings.quietHours = quiet }
        if let cap = patch.dailyCap { settings.dailyCap = cap }
    }

    /// The server's own copy replaces the screen after a failed save.
    private func undo() async {
        if let truth = try? await service.settings() { settings = truth }
    }
}

private struct SettingsLoadFailure: ErrorPresentable {
    var presentationKind: ErrorPresentationKind { .other }
    var userFacingDetail: String? { nil }
}
