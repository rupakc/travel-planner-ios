import Foundation
import Networking
import Testing
import VoyagerModel
@testable import VoyagerData

struct EndpointsTests {
    struct Row { let name: String; let method: HTTPMethod; let path: String; let auth: AuthMode; let telemetry: String; let timeout: TimeoutClass }

    private func row<R>(_ name: String, _ e: Endpoint<R>) -> Row {
        Row(name: name, method: e.method, path: e.path, auth: e.auth, telemetry: e.telemetryName, timeout: e.timeout)
    }

    private var rows: [Row] {
        [
            row("login", Endpoints.login(username: "a", password: "b")),
            row("changePassword", Endpoints.changePassword(current: "a", new: "b")),
            row("me", Endpoints.me()),
            row("providers", Endpoints.providers()),
            row("setEmail", Endpoints.setEmail("a@b.c")),
            row("plans", Endpoints.plans()),
            row("plan", Endpoints.plan(id: 7)),
            row("createPlan", Endpoints.createPlan(NewPlan(name: "x"))),
            row("updatePlan", Endpoints.updatePlan(id: 7, PlanUpdate(name: "y"))),
            row("deletePlan", Endpoints.deletePlan(id: 7)),
            row("sharePlan", Endpoints.sharePlan(id: 7)),
            row("sharedPlan", Endpoints.sharedPlan(token: "SECRETtoken")),
            row("preferences", Endpoints.preferences()),
            row("putPreferences", Endpoints.putPreferences(Preferences())),
            row("tasteProfile", Endpoints.tasteProfile()),
            row("resetTaste", Endpoints.resetTasteProfile()),
            row("recentSearches", Endpoints.recentSearches()),
            row("recordRecent", Endpoints.recordRecentSearch(.object([:]))),
            row("deleteRecent", Endpoints.deleteRecentSearch(id: 9)),
            row("airports", Endpoints.airports("lis", limit: 5)),
            row("nationalities", Endpoints.nationalities("ger", limit: 5)),
            row("filtered", Endpoints.filtered(.hotels, body: .object([:]))),
            row("fareCalendar", Endpoints.fareCalendar(TravelSearchRequest())),
            row("stressTest", Endpoints.stressTest(body: .object([:]))),
            row("layover", Endpoints.layover(body: .object([:]))),
            row("discover", Endpoints.discover(body: .object([:]))),
            row("compare", Endpoints.compare(body: .object([:]))),
            row("importExtract", Endpoints.importExtract(LinkImportRequest(url: "https://x.y"))),
            row("resolvePlace", Endpoints.resolvePlace(ResolvePlaceRequest(name: "a", city: "b"))),
            row("fareWatches", Endpoints.fareWatches()),
            row("priceWatches", Endpoints.priceWatches(kind: .hotel)),
            row("createFare", Endpoints.createFareWatch(NewFareWatch())),
            row("createPrice", Endpoints.createPriceWatch(NewPriceWatch(kind: .hotel, spec: .object([:])))),
            row("matchFare", Endpoints.matchWatch(WatchMatchQuery(kind: .flight, spec: .object([:])))),
            row("matchHotel", Endpoints.matchWatch(WatchMatchQuery(kind: .hotel, spec: .object([:])))),
            row("patchFare", Endpoints.patchFareWatch(id: 3, WatchPatch())),
            row("patchPrice", Endpoints.patchPriceWatch(id: 3, WatchPatch())),
            row("deleteFare", Endpoints.deleteWatch(kind: .flight, id: 3)),
            row("deleteTrip", Endpoints.deleteWatch(kind: .trip, id: 3)),
            row("checkFare", Endpoints.checkFareWatch(id: 3)),
            row("checkPrice", Endpoints.checkPriceWatch(id: 3)),
            row("liveCheck", Endpoints.liveCheck(LiveCheckRequest(kind: .hotel, watchId: 4))),
            row("notifications", Endpoints.notifications(unreadOnly: true, limit: 10, offset: 0)),
            row("unreadCount", Endpoints.unreadCount()),
            row("markRead", Endpoints.markRead(ids: [1], all: false)),
            row("nearby", Endpoints.nearby(NearbyRequest(lat: 1, lng: 2))),
            row("registerDevice", Endpoints.registerDevice(DeviceRegistration(token: "t", platform: "ios"))),
            row("devices", Endpoints.devices()),
            row("deleteDevice", Endpoints.deleteDevice(id: 5)),
            row("unregisterDevice", Endpoints.unregisterDevice(token: "SECRETfcm")),
            row("feedback", Endpoints.feedback(FeedbackSubmission(page: "p", rating: 5, category: "praise"))),
            row("adminUsers", Endpoints.adminUsers()),
            row("createAdminUser", Endpoints.createAdminUser(NewAdminUser(username: "u", password: "p"))),
            row("deactivate", Endpoints.deactivateUser("bob")),
            row("reactivate", Endpoints.reactivateUser("bob")),
            row("resetPassword", Endpoints.resetPassword("bob", newPassword: "x")),
            row("adminFeedback", Endpoints.adminFeedback(page: nil, category: nil, minRating: nil)),
            row("telemetrySummary", Endpoints.telemetrySummary(days: 30)),
            row("health", Endpoints.health()),
            row("config", Endpoints.config()),
        ]
    }

    @Test func test_methodPathAuth() {
        func check(_ name: String, _ method: HTTPMethod, _ path: String, _ auth: AuthMode) {
            let r = rows.first { $0.name == name }
            #expect(r?.method == method, "\(name) method")
            #expect(r?.path == path, "\(name) path")
            #expect(r?.auth == auth, "\(name) auth")
        }
        check("login", .post, "/api/auth/login", .none)
        check("changePassword", .post, "/api/auth/change-password", .required)
        check("me", .get, "/api/auth/me", .required)
        check("providers", .get, "/api/auth/providers", .none)
        check("setEmail", .put, "/api/auth/email", .required)
        check("plans", .get, "/api/plans", .required)
        check("plan", .get, "/api/plans/7", .required)
        check("updatePlan", .put, "/api/plans/7", .required)
        check("deletePlan", .delete, "/api/plans/7", .required)
        check("sharePlan", .post, "/api/plans/7/share", .required)
        check("sharedPlan", .get, "/api/share/SECRETtoken", .none)
        check("putPreferences", .put, "/api/preferences", .required)
        check("resetTaste", .delete, "/api/taste-profile", .required)
        check("recordRecent", .post, "/api/recent-searches", .required)
        check("deleteRecent", .delete, "/api/recent-searches/9", .required)
        check("airports", .get, "/api/airports/search", .none)
        check("nationalities", .get, "/api/nationalities/search", .none)
        check("filtered", .post, "/api/hotels/filtered", .optional)
        check("fareCalendar", .post, "/api/flights/fare-calendar", .required)
        check("stressTest", .post, "/api/stress-test", .optional)
        check("layover", .post, "/api/layover", .optional)
        check("discover", .post, "/api/discover", .optional)
        check("compare", .post, "/api/compare/destination", .required)
        check("importExtract", .post, "/api/import/extract", .required)
        check("resolvePlace", .post, "/api/import/resolve-place", .required)
        check("priceWatches", .get, "/api/price-watches", .required)
        check("matchFare", .post, "/api/fare-watches/match", .required)
        check("matchHotel", .post, "/api/price-watches/match", .required)
        check("patchFare", .patch, "/api/fare-watches/3", .required)
        check("patchPrice", .patch, "/api/price-watches/3", .required)
        check("deleteTrip", .delete, "/api/price-watches/3", .required)
        check("checkFare", .post, "/api/fare-watches/3/check", .required)
        check("liveCheck", .post, "/api/live-check", .required)
        check("markRead", .post, "/api/notifications/read", .required)
        check("nearby", .post, "/api/nearby", .required)
        check("registerDevice", .post, "/api/devices", .required)
        check("deleteDevice", .delete, "/api/devices/5", .required)
        check("unregisterDevice", .post, "/api/devices/unregister", .required)
        check("feedback", .post, "/api/feedback", .required)
        check("deactivate", .delete, "/api/admin/users/bob", .required)
        check("reactivate", .post, "/api/admin/users/bob/reactivate", .required)
        check("resetPassword", .post, "/api/admin/users/bob/reset-password", .required)
        check("telemetrySummary", .get, "/api/admin/telemetry/summary", .required)
        check("health", .get, "/health", .none)
        check("config", .get, "/api/config", .none)
        #expect(Endpoints.searchPath == "/api/search")
        #expect(Endpoints.searchAuth == .optional)
        #expect(Endpoints.chatPath == "/api/chat")
        #expect(Endpoints.chatAuth == .required)
    }

    @Test func test_telemetryNamesAreTemplatesWithoutIdsOrTokens() {
        for r in rows {
            #expect(r.telemetry.hasPrefix("/"), "\(r.name)")
            #expect(!r.telemetry.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }, "\(r.name): \(r.telemetry)")
            #expect(!r.telemetry.contains("SECRET"), "\(r.name)")
            #expect(!r.telemetry.contains("bob"), "\(r.name)")
            #expect(!r.telemetry.contains("?"), "\(r.name)")
        }
        let byName = Dictionary(uniqueKeysWithValues: rows.map { ($0.name, $0.telemetry) })
        #expect(byName["plan"] == "/api/plans/:id")
        #expect(byName["sharedPlan"] == "/api/share/:token")
        #expect(byName["deactivate"] == "/api/admin/users/:username")
        #expect(byName["checkPrice"] == "/api/price-watches/:id/check")
    }

    @Test func test_aiRoutesUseTheLongTimeout() {
        for name in ["filtered", "fareCalendar", "stressTest", "layover", "discover", "compare", "importExtract", "nearby", "liveCheck", "checkFare", "checkPrice"] {
            #expect(rows.first { $0.name == name }?.timeout == .ai, "\(name)")
        }
        #expect(rows.first { $0.name == "plans" }?.timeout == .standard)
    }

    @Test func test_queryItems() {
        #expect(Endpoints.notifications(unreadOnly: true, limit: 10, offset: 20).query.map { "\($0.name)=\($0.value ?? "")" }
            == ["unread_only=true", "limit=10", "offset=20"])
        #expect(Endpoints.priceWatches(kind: nil).query.isEmpty)
        #expect(Endpoints.adminFeedback(page: "results", category: nil, minRating: 3).query.map(\.name) == ["page", "min_rating"])
    }

    @Test func test_localeRule() throws {
        let set = try RequestBody.withLocale(TravelSearchRequest(destination: "Rome", locale: .fr), .de)
        #expect(set["locale"].string == "fr", "a caller-set locale wins")
        let injected = try RequestBody.withLocale(TravelSearchRequest(destination: "Rome"), .de)
        #expect(injected["locale"].string == "de")
        #expect(injected["destination"].string == "Rome")
        let merged = try RequestBody.merged(TravelSearchRequest(destination: "Rome"), extra: .object(["max_stops": 1]), .zh)
        #expect(merged["max_stops"].int == 1)
        #expect(merged["locale"].string == "zh")
    }
}
