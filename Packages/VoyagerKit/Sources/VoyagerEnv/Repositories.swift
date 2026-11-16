import Foundation
import Networking
import VoyagerData
import VoyagerModel

/// Every repository the features use. Live ones come from `Repositories.live`, fakes from TestSupport.
public struct Repositories: Sendable {
    public var plans: any PlansRepository
    public var preferences: any PreferencesRepository
    public var recent: any RecentSearchesRepository
    public var reference: any ReferenceRepository
    public var search: any SearchRepository
    public var chat: any ChatRepository
    public var agents: any AgentsRepository
    public var discover: any DiscoverRepository
    public var compare: any CompareRepository
    public var importer: any ImportRepository
    public var watches: any WatchesRepository
    public var notifications: any NotificationsRepository
    public var nearby: any NearbyRepository
    public var devices: any DevicesRepository
    public var feedback: any FeedbackRepository
    public var admin: any AdminRepository
    public var health: any HealthRepository
    /// Price alerts 2.0 (Phase 3): called only when `RemoteFeatures` says the routes exist.
    public var alertsV2: any AlertsV2Repository
    /// Notifications 2.0 (Phase 6): called only when `RemoteFeatures` says the routes exist.
    public var notificationSettings: any NotificationSettingsRepository
    public var notificationCatalog: any NotificationCatalogRepository
    /// Share links 2.0 (Phase 4): called only when `features.sharing >= 1`.
    public var shares: any SharesRepository
    /// Social and Play (Phase 5): called only when `features.social` / `features.play` are on.
    public var social: any SocialRepository
    public var play: any PlayRepository

    public init(
        plans: any PlansRepository,
        preferences: any PreferencesRepository,
        recent: any RecentSearchesRepository,
        reference: any ReferenceRepository,
        search: any SearchRepository,
        chat: any ChatRepository,
        agents: any AgentsRepository,
        discover: any DiscoverRepository,
        compare: any CompareRepository,
        importer: any ImportRepository,
        watches: any WatchesRepository,
        notifications: any NotificationsRepository,
        nearby: any NearbyRepository,
        devices: any DevicesRepository,
        feedback: any FeedbackRepository,
        admin: any AdminRepository,
        health: any HealthRepository,
        alertsV2: any AlertsV2Repository,
        notificationSettings: any NotificationSettingsRepository,
        notificationCatalog: any NotificationCatalogRepository,
        shares: any SharesRepository,
        social: any SocialRepository,
        play: any PlayRepository
    ) {
        self.plans = plans
        self.preferences = preferences
        self.recent = recent
        self.reference = reference
        self.search = search
        self.chat = chat
        self.agents = agents
        self.discover = discover
        self.compare = compare
        self.importer = importer
        self.watches = watches
        self.notifications = notifications
        self.nearby = nearby
        self.devices = devices
        self.feedback = feedback
        self.admin = admin
        self.health = health
        self.alertsV2 = alertsV2
        self.notificationSettings = notificationSettings
        self.notificationCatalog = notificationCatalog
        self.shares = shares
        self.social = social
        self.play = play
    }

    /// The live repositories over one `APIClient` and one `SSEClient`. `locale` is read per request.
    public static func live(
        api: APIClient, sse: SSEClient, locale: @escaping @Sendable () -> AppLanguage
    ) -> Repositories {
        Repositories(
            plans: LivePlansRepository(api: api, locale: locale),
            preferences: LivePreferencesRepository(api: api, locale: locale),
            recent: LiveRecentSearchesRepository(api: api, locale: locale),
            reference: LiveReferenceRepository(api: api, locale: locale),
            search: LiveSearchRepository(sse: sse, locale: locale),
            chat: LiveChatRepository(sse: sse, locale: locale),
            agents: LiveAgentsRepository(api: api, locale: locale),
            discover: LiveDiscoverRepository(api: api, locale: locale),
            compare: LiveCompareRepository(api: api, locale: locale),
            importer: LiveImportRepository(api: api, locale: locale),
            watches: LiveWatchesRepository(api: api, locale: locale),
            notifications: LiveNotificationsRepository(api: api, locale: locale),
            nearby: LiveNearbyRepository(api: api, locale: locale),
            devices: LiveDevicesRepository(api: api, locale: locale),
            feedback: LiveFeedbackRepository(api: api, locale: locale),
            admin: LiveAdminRepository(api: api, locale: locale),
            health: LiveHealthRepository(api: api, locale: locale),
            alertsV2: LiveAlertsV2Repository(api: api, locale: locale),
            notificationSettings: LiveNotificationSettingsRepository(api: api, locale: locale),
            notificationCatalog: CachedNotificationCatalogRepository(
                network: LiveNotificationCatalogRepository(api: api, locale: locale),
                store: CachedNotificationCatalogRepository.cachesStore()),
            shares: LiveSharesRepository(api: api, locale: locale),
            social: LiveSocialRepository(api: api, locale: locale),
            play: LivePlayRepository(api: api, locale: locale))
    }
}
