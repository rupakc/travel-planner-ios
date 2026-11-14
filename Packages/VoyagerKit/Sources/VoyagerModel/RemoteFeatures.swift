import Foundation

/// The Phase 3-6 flags of `GET /api/config` `features`, decoded once with safe defaults: an absent, `null` or
/// wrong-typed key is 0 / false, and unknown keys are ignored. The app never calls a route whose flag is off, so
/// an older backend (or a missing `/config`) just keeps today's screens.
public struct RemoteFeatures: Sendable, Hashable {
    /// `alerts_api`: 2 when the Phase 3 routes exist.
    public var alertsAPI: Int
    public var priceAlertsV2: Bool
    /// `live_prices`: a SerpAPI key is configured on the server.
    public var livePrices: Bool
    /// `sharing`: 1 when share links 2.0 exist.
    public var sharing: Int
    /// `notifications_api`: 1 when the notification settings and catalog routes exist.
    public var notificationsAPI: Int
    public var notificationsV2: Bool
    /// `apns`: an Apple key is configured, so the server can push to iOS devices.
    public var apns: Bool
    public var social: Bool
    public var play: Bool
    public var game: Bool

    /// Everything off.
    public init(
        alertsAPI: Int = 0, priceAlertsV2: Bool = false, livePrices: Bool = false, sharing: Int = 0,
        notificationsAPI: Int = 0, notificationsV2: Bool = false, apns: Bool = false,
        social: Bool = false, play: Bool = false, game: Bool = false
    ) {
        self.alertsAPI = alertsAPI
        self.priceAlertsV2 = priceAlertsV2
        self.livePrices = livePrices
        self.sharing = sharing
        self.notificationsAPI = notificationsAPI
        self.notificationsV2 = notificationsV2
        self.apns = apns
        self.social = social
        self.play = play
        self.game = game
    }

    public init(features: [String: JSONValue]) {
        func level(_ key: String) -> Int {
            guard let value = features[key] else { return 0 }
            if let flag = value.bool { return flag ? 1 : 0 }
            return max(0, value.int ?? 0)
        }
        func flag(_ key: String) -> Bool { level(key) > 0 }
        self.init(
            alertsAPI: level("alerts_api"), priceAlertsV2: flag("price_alerts_v2"), livePrices: flag("live_prices"),
            sharing: level("sharing"), notificationsAPI: level("notifications_api"),
            notificationsV2: flag("notifications_v2"), apns: flag("apns"),
            social: flag("social"), play: flag("play"), game: flag("game"))
    }

    /// `nil` (config not loaded, or an older backend) means everything off.
    public init(config: ClientConfig?) {
        self.init(features: config?.features ?? [:])
    }

    // MARK: Derived gates (plan rulings R3, R7, R16)

    /// The Phase 3 price-story, savings and prefs routes exist.
    public var hasAlertsV2: Bool { alertsAPI >= 2 }
    /// One-tap watch and suggestions: live prices and the v2 controls (R3).
    public var showsQuickWatch: Bool { livePrices && (priceAlertsV2 || alertsAPI >= 2) }
    public var hasSharingV2: Bool { sharing >= 1 }
    public var hasNotificationSettings: Bool { notificationsAPI >= 1 }
    /// Server push to this device can work: the server pushes by category and has an Apple key (R9, R16).
    public var serverPushLive: Bool { notificationsV2 && apns }
}

extension ClientConfig {
    public var remoteFeatures: RemoteFeatures { RemoteFeatures(features: features) }
}
