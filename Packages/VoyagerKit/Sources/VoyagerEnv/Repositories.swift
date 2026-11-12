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
        health: any HealthRepository
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
            health: LiveHealthRepository(api: api, locale: locale))
    }
}
