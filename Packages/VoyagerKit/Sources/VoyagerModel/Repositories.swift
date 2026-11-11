import Foundation

// Repository protocols. Every method is `async throws` and untyped about the error, so
// VoyagerModel does not depend on Networking: the live implementations (VoyagerData) throw
// `APIError`, fakes throw whatever a test needs.

public protocol PlansRepository: Sendable {
    func list() async throws -> [PlanSummary]
    func get(id: Int) async throws -> SavedPlan
    func create(_ plan: NewPlan) async throws -> SavedPlan
    func update(id: Int, _ update: PlanUpdate) async throws -> SavedPlan
    func delete(id: Int) async throws
    /// The plan's public share token (the existing one when there is one).
    func share(id: Int) async throws -> String
    func shared(token: String) async throws -> SharedPlan
}

public protocol PreferencesRepository: Sendable {
    func get() async throws -> Preferences
    func put(_ preferences: Preferences) async throws -> Preferences
    func taste() async throws -> TasteProfile
    func resetTaste() async throws
    /// Sets (or, with `""`, clears) the account email; answers the stored address.
    func setEmail(_ email: String) async throws -> String?
}

public protocol RecentSearchesRepository: Sendable {
    func list() async throws -> [RecentSearch]
    func record(_ search: JSONValue) async throws
    func delete(id: Int) async throws
}

public protocol ReferenceRepository: Sendable {
    func airports(_ query: String, limit: Int) async throws -> [AirportSuggestion]
    func nationalities(_ query: String, limit: Int) async throws -> [NationalitySuggestion]
}

public protocol SearchRepository: Sendable {
    func stream(_ request: TravelSearchRequest) -> AsyncThrowingStream<SearchStreamEvent, Error>
}

public protocol ChatRepository: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

/// The sections that have a `/filtered` route.
public enum FilterableSection: String, Sendable, Hashable, CaseIterable {
    case flights, hotels, activities
}

public protocol AgentsRepository: Sendable {
    func filtered(_ section: FilterableSection, request: TravelSearchRequest, filters: JSONValue) async throws -> JSONValue
    func fareCalendar(_ request: TravelSearchRequest) async throws -> JSONValue
    func stressTest(itinerary: JSONValue, request: TravelSearchRequest) async throws -> JSONValue
    func layover(_ body: JSONValue) async throws -> JSONValue
}

public protocol DiscoverRepository: Sendable {
    func suggestions(_ request: DiscoverRequest) async throws -> [DiscoverSuggestion]
}

public protocol CompareRepository: Sendable {
    func summary(_ request: TravelSearchRequest) async throws -> CompareSummary
}

public protocol ImportRepository: Sendable {
    func extract(_ request: LinkImportRequest) async throws -> LinkImportResult
    /// `{place, destination}` as sent by the backend.
    func resolvePlace(_ request: ResolvePlaceRequest) async throws -> JSONValue
}

public protocol WatchesRepository: Sendable {
    func fareWatches() async throws -> [FareWatch]
    func priceWatches(kind: WatchKind?) async throws -> [PriceWatch]
    func createFare(_ watch: NewFareWatch) async throws -> FareWatch
    func createPrice(_ watch: NewPriceWatch) async throws -> PriceWatch
    /// The caller's existing watch for the subject (the raw watch object), or nil. No live lookup.
    func match(_ query: WatchMatchQuery) async throws -> JSONValue?
    func patch(kind: WatchKind, id: Int, _ patch: WatchPatch) async throws -> WatchItem
    func delete(kind: WatchKind, id: Int) async throws
    /// "Check now": one live check.
    func check(kind: WatchKind, id: Int) async throws -> WatchItem
    func liveCheck(_ request: LiveCheckRequest) async throws -> LiveCheckResult
}

public protocol NotificationsRepository: Sendable {
    func page(unreadOnly: Bool, limit: Int, offset: Int) async throws -> NotificationsPage
    func unreadCount() async throws -> Int
    /// Marks `ids` (or everything with `all`) read; answers the new unread count.
    func markRead(ids: [Int]?, all: Bool) async throws -> Int
}

public protocol NearbyRepository: Sendable {
    func nearby(_ request: NearbyRequest) async throws -> NearbyResponse
}

public protocol DevicesRepository: Sendable {
    func register(_ registration: DeviceRegistration) async throws -> Device
    func list() async throws -> [Device]
    func delete(id: Int) async throws
    /// Sign-out: forgets the full token sent in the body (idempotent).
    func unregister(token: String) async throws
}

public protocol FeedbackRepository: Sendable {
    func submit(_ feedback: FeedbackSubmission) async throws
}

public protocol AdminRepository: Sendable {
    func users() async throws -> [AdminUser]
    func create(_ user: NewAdminUser) async throws -> AdminUser
    func deactivate(_ username: String) async throws
    func reactivate(_ username: String) async throws
    func resetPassword(_ username: String, newPassword: String) async throws
    func feedback(page: String?, category: String?, minRating: Int?) async throws -> [FeedbackEntry]
    func telemetrySummary(days: Int) async throws -> TelemetrySummary
}

public protocol HealthRepository: Sendable {
    func health() async throws -> Health
    /// `GET /api/config`; nil when the backend answers 404 (older backend: telemetry and flags off).
    func clientConfig() async throws -> ClientConfig?
}
