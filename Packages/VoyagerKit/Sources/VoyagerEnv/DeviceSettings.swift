import Foundation
import Observation

/// Per-device settings in `UserDefaults` (keys prefixed `tp_`, like the web's storage keys).
/// Every setter writes through immediately; `UserDefaults` is in memory after its first read.
@MainActor @Observable
public final class DeviceSettings {
    public enum Keys {
        public static let onboardingCompleted = "tp_onboarding_completed"
        public static let onboardingStep = "tp_onboarding_step"
        public static let travellerTypes = "tp_traveller_types"
        public static let quizAnswers = "tp_quiz_answers"
        public static let featureEnabled = "tp_feature_enabled"
        public static let featureDisabled = "tp_feature_disabled"
        public static let reminderOptIn = "tp_reminder_opt_in"
        public static let nearbyInvites = "tp_nearby_invites"
        public static let alertPoll = "tp_alert_poll"
        public static let pushToken = "tp_push_token"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) }
    }

    /// The onboarding step to resume at (0-based), so a skipped or interrupted onboarding resumes.
    public var onboardingStep: Int {
        didSet { defaults.set(onboardingStep, forKey: Keys.onboardingStep) }
    }

    public var travellerTypes: [String] {
        didSet { defaults.set(travellerTypes, forKey: Keys.travellerTypes) }
    }

    /// Quiz question id → chosen option ids.
    public var quizAnswers: [String: [String]] {
        didSet { defaults.set(quizAnswers, forKey: Keys.quizAnswers) }
    }

    /// Features the user switched on or off explicitly (ids from Domain's feature list).
    public var featureEnabled: Set<String> {
        didSet { defaults.set(featureEnabled.sorted(), forKey: Keys.featureEnabled) }
    }

    public var featureDisabled: Set<String> {
        didSet { defaults.set(featureDisabled.sorted(), forKey: Keys.featureDisabled) }
    }

    public var reminderOptIn: Bool {
        didSet { defaults.set(reminderOptIn, forKey: Keys.reminderOptIn) }
    }

    public var nearbyInvites: Bool {
        didSet { defaults.set(nearbyInvites, forKey: Keys.nearbyInvites) }
    }

    /// Whether the app looks for new alerts every minute while it is open (on by default).
    public var alertPoll: Bool {
        didSet { defaults.set(alertPoll, forKey: Keys.alertPoll) }
    }

    /// The device's push token, once one was registered; sign-out unregisters it.
    public var pushToken: String? {
        didSet { defaults.set(pushToken, forKey: Keys.pushToken) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        onboardingStep = max(defaults.integer(forKey: Keys.onboardingStep), 0)
        travellerTypes = defaults.stringArray(forKey: Keys.travellerTypes) ?? []
        quizAnswers = Self.answers(defaults.dictionary(forKey: Keys.quizAnswers))
        featureEnabled = Set(defaults.stringArray(forKey: Keys.featureEnabled) ?? [])
        featureDisabled = Set(defaults.stringArray(forKey: Keys.featureDisabled) ?? [])
        reminderOptIn = defaults.bool(forKey: Keys.reminderOptIn)
        nearbyInvites = defaults.bool(forKey: Keys.nearbyInvites)
        alertPoll = defaults.object(forKey: Keys.alertPoll) as? Bool ?? true
        pushToken = defaults.string(forKey: Keys.pushToken)
    }

    private static func answers(_ raw: [String: Any]?) -> [String: [String]] {
        guard let raw else { return [:] }
        var result: [String: [String]] = [:]
        for (key, value) in raw {
            if let list = value as? [String] { result[key] = list }
        }
        return result
    }
}
