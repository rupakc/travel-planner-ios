import Foundation
import VoyagerEnv
import VoyagerModel

// Fake inputs mirror the protocol's parameter lists, some of which have three parameters.
// swiftlint:disable large_tuple

// Fakes for every repository. Each method is a `FakeCall` named `on<Method>`: script it with `returns`, `fails`
// or `handler`, then read `calls`. Lists default to `[]`, writes to success, everything else throws
// `FakeRepositoryError.notScripted`. `/api/config` defaults to nil (an older backend).

public final class FakePlansRepository: PlansRepository {
    public let onList = FakeCall<Void, [PlanSummary]>("plans.list") { _ in [] }
    public let onGet = FakeCall<Int, SavedPlan>("plans.get")
    public let onCreate = FakeCall<NewPlan, SavedPlan>("plans.create")
    public let onUpdate = FakeCall<(id: Int, update: PlanUpdate), SavedPlan>("plans.update")
    public let onDelete = FakeCall<Int, Void>("plans.delete") { _ in }
    public let onShare = FakeCall<Int, String>("plans.share")
    public let onShared = FakeCall<String, SharedPlan>("plans.shared")
    public init() {}

    public func list() async throws -> [PlanSummary] { try await onList() }
    public func get(id: Int) async throws -> SavedPlan { try await onGet(id) }
    public func create(_ plan: NewPlan) async throws -> SavedPlan { try await onCreate(plan) }
    public func update(id: Int, _ update: PlanUpdate) async throws -> SavedPlan { try await onUpdate((id, update)) }
    public func delete(id: Int) async throws { try await onDelete(id) }
    public func share(id: Int) async throws -> String { try await onShare(id) }
    public func shared(token: String) async throws -> SharedPlan { try await onShared(token) }
}

public final class FakePreferencesRepository: PreferencesRepository {
    public let onGet = FakeCall<Void, Preferences>("preferences.get")
    public let onPut = FakeCall<Preferences, Preferences>("preferences.put") { $0 }
    public let onTaste = FakeCall<Void, TasteProfile>("preferences.taste")
    public let onResetTaste = FakeCall<Void, Void>("preferences.resetTaste") { _ in }
    public let onSetEmail = FakeCall<String, String?>("preferences.setEmail") { $0.isEmpty ? nil : $0 }
    public init() {}

    public func get() async throws -> Preferences { try await onGet() }
    public func put(_ preferences: Preferences) async throws -> Preferences { try await onPut(preferences) }
    public func taste() async throws -> TasteProfile { try await onTaste() }
    public func resetTaste() async throws { try await onResetTaste() }
    public func setEmail(_ email: String) async throws -> String? { try await onSetEmail(email) }
}

public final class FakeRecentSearchesRepository: RecentSearchesRepository {
    public let onList = FakeCall<Void, [RecentSearch]>("recent.list") { _ in [] }
    public let onRecord = FakeCall<JSONValue, Void>("recent.record") { _ in }
    public let onDelete = FakeCall<Int, Void>("recent.delete") { _ in }
    public init() {}

    public func list() async throws -> [RecentSearch] { try await onList() }
    public func record(_ search: JSONValue) async throws { try await onRecord(search) }
    public func delete(id: Int) async throws { try await onDelete(id) }
}

public final class FakeReferenceRepository: ReferenceRepository {
    public let onAirports = FakeCall<(query: String, limit: Int), [AirportSuggestion]>("reference.airports") { _ in [] }
    public let onNationalities = FakeCall<(query: String, limit: Int), [NationalitySuggestion]>("reference.nationalities") { _ in [] }
    public init() {}

    public func airports(_ query: String, limit: Int) async throws -> [AirportSuggestion] { try await onAirports((query, limit)) }
    public func nationalities(_ query: String, limit: Int) async throws -> [NationalitySuggestion] {
        try await onNationalities((query, limit))
    }
}

public final class FakeSearchRepository: SearchRepository {
    public let onStream = FakeStreamCall<TravelSearchRequest, SearchStreamEvent>("search.stream")
    public init() {}

    public func stream(_ request: TravelSearchRequest) -> AsyncThrowingStream<SearchStreamEvent, Error> { onStream(request) }
}

public final class FakeChatRepository: ChatRepository {
    public let onStream = FakeStreamCall<ChatRequest, ChatStreamEvent>("chat.stream")
    public init() {}

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> { onStream(request) }
}

public final class FakeAgentsRepository: AgentsRepository {
    public let onFiltered = FakeCall<(section: FilterableSection, request: TravelSearchRequest, filters: JSONValue), JSONValue>(
        "agents.filtered")
    public let onFareCalendar = FakeCall<TravelSearchRequest, JSONValue>("agents.fareCalendar")
    public let onStressTest = FakeCall<(itinerary: JSONValue, request: TravelSearchRequest), JSONValue>("agents.stressTest")
    public let onLayover = FakeCall<JSONValue, JSONValue>("agents.layover")
    public init() {}

    public func filtered(_ section: FilterableSection, request: TravelSearchRequest, filters: JSONValue) async throws -> JSONValue {
        try await onFiltered((section, request, filters))
    }
    public func fareCalendar(_ request: TravelSearchRequest) async throws -> JSONValue { try await onFareCalendar(request) }
    public func stressTest(itinerary: JSONValue, request: TravelSearchRequest) async throws -> JSONValue {
        try await onStressTest((itinerary, request))
    }
    public func layover(_ body: JSONValue) async throws -> JSONValue { try await onLayover(body) }
}

public final class FakeDiscoverRepository: DiscoverRepository {
    public let onSuggestions = FakeCall<DiscoverRequest, [DiscoverSuggestion]>("discover.suggestions") { _ in [] }
    public init() {}

    public func suggestions(_ request: DiscoverRequest) async throws -> [DiscoverSuggestion] { try await onSuggestions(request) }
}

public final class FakeCompareRepository: CompareRepository {
    public let onSummary = FakeCall<TravelSearchRequest, CompareSummary>("compare.summary")
    public init() {}

    public func summary(_ request: TravelSearchRequest) async throws -> CompareSummary { try await onSummary(request) }
}

public final class FakeImportRepository: ImportRepository {
    public let onExtract = FakeCall<LinkImportRequest, LinkImportResult>("import.extract")
    public let onResolvePlace = FakeCall<ResolvePlaceRequest, JSONValue>("import.resolvePlace")
    public init() {}

    public func extract(_ request: LinkImportRequest) async throws -> LinkImportResult { try await onExtract(request) }
    public func resolvePlace(_ request: ResolvePlaceRequest) async throws -> JSONValue { try await onResolvePlace(request) }
}

public final class FakeWatchesRepository: WatchesRepository {
    public let onFareWatches = FakeCall<Void, [FareWatch]>("watches.fareWatches") { _ in [] }
    public let onPriceWatches = FakeCall<WatchKind?, [PriceWatch]>("watches.priceWatches") { _ in [] }
    public let onCreateFare = FakeCall<NewFareWatch, FareWatch>("watches.createFare")
    public let onCreatePrice = FakeCall<NewPriceWatch, PriceWatch>("watches.createPrice")
    public let onMatch = FakeCall<WatchMatchQuery, JSONValue?>("watches.match") { _ in nil }
    public let onPatch = FakeCall<(kind: WatchKind, id: Int, patch: WatchPatch), WatchItem>("watches.patch")
    public let onDelete = FakeCall<(kind: WatchKind, id: Int), Void>("watches.delete") { _ in }
    public let onCheck = FakeCall<(kind: WatchKind, id: Int), WatchItem>("watches.check")
    public let onLiveCheck = FakeCall<LiveCheckRequest, LiveCheckResult>("watches.liveCheck")
    public init() {}

    public func fareWatches() async throws -> [FareWatch] { try await onFareWatches() }
    public func priceWatches(kind: WatchKind?) async throws -> [PriceWatch] { try await onPriceWatches(kind) }
    public func createFare(_ watch: NewFareWatch) async throws -> FareWatch { try await onCreateFare(watch) }
    public func createPrice(_ watch: NewPriceWatch) async throws -> PriceWatch { try await onCreatePrice(watch) }
    public func match(_ query: WatchMatchQuery) async throws -> JSONValue? { try await onMatch(query) }
    public func patch(kind: WatchKind, id: Int, _ patch: WatchPatch) async throws -> WatchItem { try await onPatch((kind, id, patch)) }
    public func delete(kind: WatchKind, id: Int) async throws { try await onDelete((kind, id)) }
    public func check(kind: WatchKind, id: Int) async throws -> WatchItem { try await onCheck((kind, id)) }
    public func liveCheck(_ request: LiveCheckRequest) async throws -> LiveCheckResult { try await onLiveCheck(request) }
}

public final class FakeNotificationsRepository: NotificationsRepository {
    public let onPage = FakeCall<(unreadOnly: Bool, limit: Int, offset: Int), NotificationsPage>("notifications.page")
    public let onUnreadCount = FakeCall<Void, Int>("notifications.unreadCount") { _ in 0 }
    public let onMarkRead = FakeCall<(ids: [Int]?, all: Bool), Int>("notifications.markRead") { _ in 0 }
    public init() {}

    public func page(unreadOnly: Bool, limit: Int, offset: Int) async throws -> NotificationsPage {
        try await onPage((unreadOnly, limit, offset))
    }
    public func unreadCount() async throws -> Int { try await onUnreadCount() }
    public func markRead(ids: [Int]?, all: Bool) async throws -> Int { try await onMarkRead((ids, all)) }
}

public final class FakeNearbyRepository: NearbyRepository {
    public let onNearby = FakeCall<NearbyRequest, NearbyResponse>("nearby.nearby")
    public init() {}

    public func nearby(_ request: NearbyRequest) async throws -> NearbyResponse { try await onNearby(request) }
}

public final class FakeDevicesRepository: DevicesRepository {
    public let onRegister = FakeCall<DeviceRegistration, Device>("devices.register")
    public let onList = FakeCall<Void, [Device]>("devices.list") { _ in [] }
    public let onDelete = FakeCall<Int, Void>("devices.delete") { _ in }
    public let onUnregister = FakeCall<String, Void>("devices.unregister") { _ in }
    public init() {}

    public func register(_ registration: DeviceRegistration) async throws -> Device { try await onRegister(registration) }
    public func list() async throws -> [Device] { try await onList() }
    public func delete(id: Int) async throws { try await onDelete(id) }
    public func unregister(token: String) async throws { try await onUnregister(token) }
}

public final class FakeFeedbackRepository: FeedbackRepository {
    public let onSubmit = FakeCall<FeedbackSubmission, Void>("feedback.submit") { _ in }
    public init() {}

    public func submit(_ feedback: FeedbackSubmission) async throws { try await onSubmit(feedback) }
}

public final class FakeAdminRepository: AdminRepository {
    public let onUsers = FakeCall<Void, [AdminUser]>("admin.users") { _ in [] }
    public let onCreate = FakeCall<NewAdminUser, AdminUser>("admin.create")
    public let onDeactivate = FakeCall<String, Void>("admin.deactivate") { _ in }
    public let onReactivate = FakeCall<String, Void>("admin.reactivate") { _ in }
    public let onResetPassword = FakeCall<(username: String, newPassword: String), Void>("admin.resetPassword") { _ in }
    public let onFeedback = FakeCall<(page: String?, category: String?, minRating: Int?), [FeedbackEntry]>("admin.feedback") { _ in [] }
    public let onTelemetrySummary = FakeCall<Int, TelemetrySummary>("admin.telemetrySummary")
    public init() {}

    public func users() async throws -> [AdminUser] { try await onUsers() }
    public func create(_ user: NewAdminUser) async throws -> AdminUser { try await onCreate(user) }
    public func deactivate(_ username: String) async throws { try await onDeactivate(username) }
    public func reactivate(_ username: String) async throws { try await onReactivate(username) }
    public func resetPassword(_ username: String, newPassword: String) async throws {
        try await onResetPassword((username, newPassword))
    }
    public func feedback(page: String?, category: String?, minRating: Int?) async throws -> [FeedbackEntry] {
        try await onFeedback((page, category, minRating))
    }
    public func telemetrySummary(days: Int) async throws -> TelemetrySummary { try await onTelemetrySummary(days) }
}

public final class FakeHealthRepository: HealthRepository {
    public let onHealth = FakeCall<Void, Health>("health.health")
    /// Default nil: the backend has no `/api/config` (telemetry and feature flags off).
    public let onClientConfig = FakeCall<Void, ClientConfig?>("health.clientConfig") { _ in nil }
    public init() {}

    public func health() async throws -> Health { try await onHealth() }
    public func clientConfig() async throws -> ClientConfig? { try await onClientConfig() }
}

/// One fake per repository plus the auth API, all reference types: keep the struct (or a fake) to script
/// calls and to read what was called after the code under test ran.
public struct FakeRepositories: Sendable {
    public var plans = FakePlansRepository()
    public var preferences = FakePreferencesRepository()
    public var recent = FakeRecentSearchesRepository()
    public var reference = FakeReferenceRepository()
    public var search = FakeSearchRepository()
    public var chat = FakeChatRepository()
    public var agents = FakeAgentsRepository()
    public var discover = FakeDiscoverRepository()
    public var compare = FakeCompareRepository()
    public var importer = FakeImportRepository()
    public var watches = FakeWatchesRepository()
    public var notifications = FakeNotificationsRepository()
    public var nearby = FakeNearbyRepository()
    public var devices = FakeDevicesRepository()
    public var feedback = FakeFeedbackRepository()
    public var admin = FakeAdminRepository()
    public var health = FakeHealthRepository()
    public var auth = FakeAuthAPI()

    public init() {}

    public var repositories: Repositories {
        Repositories(
            plans: plans, preferences: preferences, recent: recent, reference: reference, search: search, chat: chat,
            agents: agents, discover: discover, compare: compare, importer: importer, watches: watches,
            notifications: notifications, nearby: nearby, devices: devices, feedback: feedback, admin: admin, health: health)
    }
}

/// The name the plan uses for this group of fakes.
public typealias Fakes = FakeRepositories

// swiftlint:enable large_tuple
