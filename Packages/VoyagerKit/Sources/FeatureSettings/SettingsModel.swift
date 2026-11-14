import AuthCore
import DesignSystem
import Domain
import Foundation
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// State and actions of the You tab. Telemetry and consent are injectable so tests record instead of sending.
@MainActor @Observable
final class SettingsModel {
    let env: AppEnvironment
    private(set) var telemetryOn: Bool
    private(set) var signingOut = false

    @ObservationIgnored private let track: (TelemetryEvent) -> Void
    @ObservationIgnored private let setConsent: (Bool) -> Void
    @ObservationIgnored private let readChoice: () -> ConsentChoice?
    @ObservationIgnored private let timeZone: String

    init(
        env: AppEnvironment,
        consentChoice: (() -> ConsentChoice?)? = nil,
        timeZone: String = TimeZone.current.identifier,
        track: ((TelemetryEvent) -> Void)? = nil,
        setConsent: ((Bool) -> Void)? = nil,
        telemetry: Telemetry? = nil
    ) {
        self.env = env
        let telemetry = telemetry ?? env.telemetry
        self.track = track ?? { telemetry.track($0) }
        self.setConsent = setConsent ?? { telemetry.setConsent($0) }
        let read = consentChoice ?? { telemetry.consentChoice }
        readChoice = read
        self.timeZone = timeZone
        telemetryOn = Self.isOn(choice: read(), timeZone: timeZone)
    }

    private static func isOn(choice: ConsentChoice?, timeZone: String) -> Bool {
        choice == .granted || (choice == nil && !Consent.required(timeZone: timeZone))
    }

    /// Re-reads the stored choice: the consent card can be answered outside Settings.
    func refreshConsent() {
        let next = Self.isOn(choice: readChoice(), timeZone: timeZone)
        if next != telemetryOn { telemetryOn = next }
    }

    // MARK: - Who

    var username: String { env.auth.session?.user.username ?? "" }
    var isAdmin: Bool { env.auth.session?.user.isAdmin == true }
    /// The Admin row is for admins only.
    var showsAdminRow: Bool { isAdmin }
    /// The Phase 3-6 flags of `/config`; all off until it loaded (and on an older backend).
    var features: RemoteFeatures { RemoteFeatures(config: env.clientConfig) }
    /// The rows of the Phase 3-6 screens appear only when the backend says their routes exist.
    var showsNotificationSettingsRow: Bool { features.hasNotificationSettings }
    var showsAlertPrefsRow: Bool { features.hasAlertsV2 }
    var showsMySharesRow: Bool { features.hasSharingV2 }
    var showsServerSection: Bool { env.build.isDebug }

    // MARK: - Appearance and language

    var theme: ThemePreference { env.theme.preference }

    func setTheme(_ preference: ThemePreference) {
        guard preference != env.theme.preference else { return }
        env.theme.preference = preference
        track(.themeChange(preference.rawValue))
    }

    var language: AppLanguage { env.language.language }

    /// `LanguageController` persists `tp_lang`; the shell reads `env.language.locale` into `\.locale`, so the
    /// UI re-renders without a relaunch.
    func setLanguage(_ language: AppLanguage) {
        guard language != env.language.language else { return }
        env.language.language = language
        track(.languageChange(language))
    }

    // MARK: - Privacy

    /// Off clears the queued events and sends nothing more (`Telemetry.setConsent(false)`).
    func setTelemetry(_ on: Bool) {
        guard on != telemetryOn else { return }
        telemetryOn = on
        setConsent(on)
    }

    /// "Privacy choices": the shell shows the consent card again.
    func reopenConsent() { env.consentPromptRequested = true }

    // MARK: - Features

    private var types: [TravellerType] { env.device.travellerTypes.compactMap(TravellerType.init(rawValue:)) }

    func isFeatureOn(_ id: String) -> Bool {
        FeatureCatalogue.visible(types: types, enabled: env.device.featureEnabled, disabled: env.device.featureDisabled)
            .contains(id)
    }

    func setFeature(_ id: String, on: Bool) {
        let isDefault = FeatureCatalogue.defaults(for: types).contains(id)
        if on {
            env.device.featureDisabled.remove(id)
            if !isDefault { env.device.featureEnabled.insert(id) }
        } else {
            env.device.featureEnabled.remove(id)
            if isDefault { env.device.featureDisabled.insert(id) }
        }
    }

    // MARK: - Rows and sign-out

    func open(_ route: Route) { env.router.open(route) }

    /// Unregisters the push token when there is one (a failure never blocks sign-out and keeps the token), then signs out.
    func signOut() async {
        guard !signingOut else { return }
        signingOut = true
        if let token = env.device.pushToken, !token.isEmpty {
            // Keep the token when unregistering fails, so a later sign-out (or launch) can retry.
            do {
                try await env.repos.devices.unregister(token: token)
                env.device.pushToken = nil
            } catch {}
        }
        await env.auth.signOut()
        signingOut = false
    }
}
