import Foundation
import AuthCore
import Networking
import VoyagerModel

/// Response wrappers for the few routes that answer a small envelope.
public struct ShareTokenResponse: Decodable, Sendable, Equatable { public let shareToken: String
    enum CodingKeys: String, CodingKey { case shareToken = "share_token" }
}
public struct CountResponse: Decodable, Sendable, Equatable { public let count: Int }
public struct UnreadResponse: Decodable, Sendable, Equatable { public let unread: Int }
public struct EmailResponse: Decodable, Sendable, Equatable { public let email: String? }
public struct WatchEnvelope: Decodable, Sendable, Equatable { public let watch: JSONValue? }
public struct DevicesEnvelope: Decodable, Sendable, Equatable { public let items: [Device] }
public struct AccessTokenResponse: Decodable, Sendable, Equatable {
    public let accessToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}

/// Request bodies built from typed models plus the web's `localeField()` rule.
public enum RequestBody {
    /// Encodes `value` and adds `locale` (the base language code) unless the caller already set one.
    public static func withLocale(_ value: some Encodable, _ locale: AppLanguage) throws -> JSONValue {
        var object = try object(of: value)
        if (object["locale"]?.string ?? "").isEmpty { object["locale"] = .string(locale.rawValue) }
        return .object(object)
    }

    /// `request` fields, then `extra` entries on top (`/filtered` filters, stress-test `itinerary`), then locale.
    public static func merged(_ request: some Encodable, extra: JSONValue, _ locale: AppLanguage) throws -> JSONValue {
        var fields = try object(of: request)
        for (key, value) in extra.object ?? [:] { fields[key] = value }
        if (fields["locale"]?.string ?? "").isEmpty { fields["locale"] = .string(locale.rawValue) }
        return .object(fields)
    }

    static func object(of value: some Encodable) throws -> [String: JSONValue] {
        let data = try JSONEncoder().encode(value)
        guard case .object(let fields) = try JSONDecoder().decode(JSONValue.self, from: data) else {
            throw APIError.decoding
        }
        return fields
    }
}

/// One static factory per API row: method, path, auth mode, timeout class and a telemetry route template.
/// Auth modes follow docs/API-Reference.md ("Endpoint index").
public enum Endpoints {
    // MARK: Auth
    public static func login(username: String, password: String) -> Endpoint<LoginResponse> {
        Endpoint(method: .post, path: "/api/auth/login", telemetryName: "/api/auth/login",
                 body: JSONValue.object(["username": .string(username), "password": .string(password)]), auth: .none)
    }
    public static func changePassword(current: String, new: String) -> Endpoint<AccessTokenResponse> {
        Endpoint(method: .post, path: "/api/auth/change-password", telemetryName: "/api/auth/change-password",
                 body: JSONValue.object(["current_password": .string(current), "new_password": .string(new)]))
    }
    public static func me() -> Endpoint<User> { Endpoint(path: "/api/auth/me", telemetryName: "/api/auth/me") }
    public static func providers() -> Endpoint<JSONValue> {
        Endpoint(path: "/api/auth/providers", telemetryName: "/api/auth/providers", auth: .none)
    }
    public static func setEmail(_ email: String) -> Endpoint<EmailResponse> {
        Endpoint(method: .put, path: "/api/auth/email", telemetryName: "/api/auth/email", body: JSONValue.object(["email": .string(email)]))
    }

    // MARK: Plans
    public static func plans() -> Endpoint<[PlanSummary]> { Endpoint(path: "/api/plans", telemetryName: "/api/plans") }
    public static func plan(id: Int) -> Endpoint<SavedPlan> {
        Endpoint(path: "/api/plans/\(id)", telemetryName: "/api/plans/:id")
    }
    public static func createPlan(_ plan: NewPlan) -> Endpoint<SavedPlan> {
        Endpoint(method: .post, path: "/api/plans", telemetryName: "/api/plans", body: plan)
    }
    public static func updatePlan(id: Int, _ update: PlanUpdate) -> Endpoint<SavedPlan> {
        Endpoint(method: .put, path: "/api/plans/\(id)", telemetryName: "/api/plans/:id", body: update)
    }
    public static func deletePlan(id: Int) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/plans/\(id)", telemetryName: "/api/plans/:id")
    }
    public static func sharePlan(id: Int) -> Endpoint<ShareTokenResponse> {
        Endpoint(method: .post, path: "/api/plans/\(id)/share", telemetryName: "/api/plans/:id/share")
    }
    public static func sharedPlan(token: String) -> Endpoint<SharedPlan> {
        Endpoint(path: "/api/share/\(token)", telemetryName: "/api/share/:token", auth: .none)
    }

    // MARK: Preferences, recent searches, taste
    public static func preferences() -> Endpoint<Preferences> {
        Endpoint(path: "/api/preferences", telemetryName: "/api/preferences")
    }
    public static func putPreferences(_ preferences: Preferences) -> Endpoint<Preferences> {
        Endpoint(method: .put, path: "/api/preferences", telemetryName: "/api/preferences", body: preferences)
    }
    public static func tasteProfile() -> Endpoint<TasteProfile> {
        Endpoint(path: "/api/taste-profile", telemetryName: "/api/taste-profile")
    }
    public static func resetTasteProfile() -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/taste-profile", telemetryName: "/api/taste-profile")
    }
    public static func recentSearches() -> Endpoint<[RecentSearch]> {
        Endpoint(path: "/api/recent-searches", telemetryName: "/api/recent-searches")
    }
    public static func recordRecentSearch(_ search: JSONValue) -> Endpoint<Empty> {
        Endpoint(method: .post, path: "/api/recent-searches", telemetryName: "/api/recent-searches", body: search)
    }
    public static func deleteRecentSearch(id: Int) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/recent-searches/\(id)", telemetryName: "/api/recent-searches/:id")
    }

    // MARK: Reference data
    public static func airports(_ query: String, limit: Int) -> Endpoint<[AirportSuggestion]> {
        Endpoint(path: "/api/airports/search", telemetryName: "/api/airports/search",
                 query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))], auth: .none)
    }
    public static func nationalities(_ query: String, limit: Int) -> Endpoint<[NationalitySuggestion]> {
        Endpoint(path: "/api/nationalities/search", telemetryName: "/api/nationalities/search",
                 query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))], auth: .none)
    }

    // MARK: Streams (paths only; SSEClient sends them)
    public static let searchPath = "/api/search"
    public static let chatPath = "/api/chat"
    public static let searchAuth = AuthMode.optional
    public static let chatAuth = AuthMode.required

    // MARK: Single-agent and helper routes
    public static func filtered(_ section: FilterableSection, body: JSONValue) -> Endpoint<JSONValue> {
        Endpoint(method: .post, path: "/api/\(section.rawValue)/filtered", telemetryName: "/api/\(section.rawValue)/filtered",
                 body: body, auth: .optional, timeout: .ai)
    }
    public static func fareCalendar(_ request: TravelSearchRequest) -> Endpoint<JSONValue> {
        Endpoint(method: .post, path: "/api/flights/fare-calendar", telemetryName: "/api/flights/fare-calendar",
                 body: request, timeout: .ai)
    }
    public static func stressTest(body: JSONValue) -> Endpoint<JSONValue> {
        Endpoint(method: .post, path: "/api/stress-test", telemetryName: "/api/stress-test",
                 body: body, auth: .optional, timeout: .ai)
    }
    public static func layover(body: JSONValue) -> Endpoint<JSONValue> {
        Endpoint(method: .post, path: "/api/layover", telemetryName: "/api/layover",
                 body: body, auth: .optional, timeout: .ai)
    }

    // MARK: Discover, compare, import
    public static func discover(body: JSONValue) -> Endpoint<DiscoverResponse> {
        Endpoint(method: .post, path: "/api/discover", telemetryName: "/api/discover",
                 body: body, auth: .optional, timeout: .ai)
    }
    public static func compare(body: JSONValue) -> Endpoint<CompareSummary> {
        Endpoint(method: .post, path: "/api/compare/destination", telemetryName: "/api/compare/destination",
                 body: body, timeout: .ai)
    }
    public static func importExtract(_ request: LinkImportRequest) -> Endpoint<LinkImportResult> {
        Endpoint(method: .post, path: "/api/import/extract", telemetryName: "/api/import/extract",
                 body: request, timeout: .ai)
    }
    public static func resolvePlace(_ request: ResolvePlaceRequest) -> Endpoint<JSONValue> {
        Endpoint(method: .post, path: "/api/import/resolve-place", telemetryName: "/api/import/resolve-place", body: request)
    }

    // MARK: Watches
    private static func base(_ kind: WatchKind) -> String { kind == .flight ? "/api/fare-watches" : "/api/price-watches" }

    public static func fareWatches() -> Endpoint<[FareWatch]> {
        Endpoint(path: "/api/fare-watches", telemetryName: "/api/fare-watches")
    }
    public static func priceWatches(kind: WatchKind?) -> Endpoint<[PriceWatch]> {
        Endpoint(path: "/api/price-watches", telemetryName: "/api/price-watches",
                 query: kind.map { [URLQueryItem(name: "kind", value: $0.rawValue)] } ?? [])
    }
    public static func createFareWatch(_ watch: NewFareWatch) -> Endpoint<FareWatch> {
        Endpoint(method: .post, path: "/api/fare-watches", telemetryName: "/api/fare-watches", body: watch)
    }
    public static func createPriceWatch(_ watch: NewPriceWatch) -> Endpoint<PriceWatch> {
        Endpoint(method: .post, path: "/api/price-watches", telemetryName: "/api/price-watches", body: watch)
    }
    public static func matchWatch(_ query: WatchMatchQuery) -> Endpoint<WatchEnvelope> {
        Endpoint(method: .post, path: base(query.kind) + "/match", telemetryName: base(query.kind) + "/match", body: query)
    }
    public static func patchFareWatch(id: Int, _ patch: WatchPatch) -> Endpoint<FareWatch> {
        Endpoint(method: .patch, path: "/api/fare-watches/\(id)", telemetryName: "/api/fare-watches/:id", body: patch)
    }
    public static func patchPriceWatch(id: Int, _ patch: WatchPatch) -> Endpoint<PriceWatch> {
        Endpoint(method: .patch, path: "/api/price-watches/\(id)", telemetryName: "/api/price-watches/:id", body: patch)
    }
    public static func deleteWatch(kind: WatchKind, id: Int) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "\(base(kind))/\(id)", telemetryName: "\(base(kind))/:id")
    }
    public static func checkFareWatch(id: Int) -> Endpoint<FareWatch> {
        Endpoint(method: .post, path: "/api/fare-watches/\(id)/check", telemetryName: "/api/fare-watches/:id/check", timeout: .ai)
    }
    public static func checkPriceWatch(id: Int) -> Endpoint<PriceWatch> {
        Endpoint(method: .post, path: "/api/price-watches/\(id)/check", telemetryName: "/api/price-watches/:id/check", timeout: .ai)
    }
    public static func liveCheck(_ request: LiveCheckRequest) -> Endpoint<LiveCheckResult> {
        Endpoint(method: .post, path: "/api/live-check", telemetryName: "/api/live-check", body: request, timeout: .ai)
    }

    // MARK: Notifications
    public static func notifications(unreadOnly: Bool, limit: Int, offset: Int) -> Endpoint<NotificationsPage> {
        Endpoint(path: "/api/notifications", telemetryName: "/api/notifications", query: [
            URLQueryItem(name: "unread_only", value: unreadOnly ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
    }
    public static func unreadCount() -> Endpoint<CountResponse> {
        Endpoint(path: "/api/notifications/unread-count", telemetryName: "/api/notifications/unread-count")
    }
    public static func markRead(ids: [Int]?, all: Bool) -> Endpoint<UnreadResponse> {
        let body: JSONValue = all ? .object(["all": .bool(true)]) : .object(["ids": .array((ids ?? []).map { .number(Double($0)) })])
        return Endpoint(method: .post, path: "/api/notifications/read", telemetryName: "/api/notifications/read", body: body)
    }

    // MARK: Nearby, devices
    public static func nearby(_ request: NearbyRequest) -> Endpoint<NearbyResponse> {
        Endpoint(method: .post, path: "/api/nearby", telemetryName: "/api/nearby", body: request, timeout: .ai)
    }
    public static func registerDevice(_ registration: DeviceRegistration) -> Endpoint<Device> {
        Endpoint(method: .post, path: "/api/devices", telemetryName: "/api/devices", body: registration)
    }
    public static func devices() -> Endpoint<DevicesEnvelope> { Endpoint(path: "/api/devices", telemetryName: "/api/devices") }
    public static func deleteDevice(id: Int) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/devices/\(id)", telemetryName: "/api/devices/:id")
    }
    public static func unregisterDevice(token: String) -> Endpoint<Empty> {
        Endpoint(method: .post, path: "/api/devices/unregister", telemetryName: "/api/devices/unregister",
                 body: JSONValue.object(["token": .string(token)]))
    }

    // MARK: Feedback, admin, health
    public static func feedback(_ feedback: FeedbackSubmission) -> Endpoint<Empty> {
        Endpoint(method: .post, path: "/api/feedback", telemetryName: "/api/feedback", body: feedback)
    }
    public static func adminUsers() -> Endpoint<[AdminUser]> { Endpoint(path: "/api/admin/users", telemetryName: "/api/admin/users") }
    public static func createAdminUser(_ user: NewAdminUser) -> Endpoint<AdminUser> {
        Endpoint(method: .post, path: "/api/admin/users", telemetryName: "/api/admin/users", body: user)
    }
    public static func deactivateUser(_ username: String) -> Endpoint<Empty> {
        Endpoint(method: .delete, path: "/api/admin/users/\(username)", telemetryName: "/api/admin/users/:username")
    }
    public static func reactivateUser(_ username: String) -> Endpoint<Empty> {
        Endpoint(method: .post, path: "/api/admin/users/\(username)/reactivate",
                 telemetryName: "/api/admin/users/:username/reactivate")
    }
    public static func resetPassword(_ username: String, newPassword: String) -> Endpoint<Empty> {
        Endpoint(method: .post, path: "/api/admin/users/\(username)/reset-password",
                 telemetryName: "/api/admin/users/:username/reset-password", body: JSONValue.object(["new_password": .string(newPassword)]))
    }
    public static func adminFeedback(page: String?, category: String?, minRating: Int?) -> Endpoint<[FeedbackEntry]> {
        var query: [URLQueryItem] = []
        if let page { query.append(URLQueryItem(name: "page", value: page)) }
        if let category { query.append(URLQueryItem(name: "category", value: category)) }
        if let minRating { query.append(URLQueryItem(name: "min_rating", value: String(minRating))) }
        return Endpoint(path: "/api/admin/feedback", telemetryName: "/api/admin/feedback", query: query)
    }
    public static func telemetrySummary(days: Int) -> Endpoint<TelemetrySummary> {
        Endpoint(path: "/api/admin/telemetry/summary", telemetryName: "/api/admin/telemetry/summary",
                 query: [URLQueryItem(name: "days", value: String(days))])
    }
    public static func health() -> Endpoint<Health> { Endpoint(path: "/health", telemetryName: "/health", auth: .none) }
    public static func config() -> Endpoint<ClientConfig> { Endpoint(path: "/api/config", telemetryName: "/api/config", auth: .none) }
}
