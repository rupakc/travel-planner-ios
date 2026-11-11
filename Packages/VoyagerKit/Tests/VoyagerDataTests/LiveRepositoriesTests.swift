import Foundation
import Networking
import Testing
import TestFixtures
import VoyagerModel
@testable import VoyagerData

struct LiveRepositoriesTests {
    private func fixtureHarness(_ name: String, status: Int = 200, language: AppLanguage = .de) throws -> Harness {
        let json = try Fixtures.string(name)
        return try Harness(language: language) { _ in .init(status: status, json: json) }
    }

    @Test func test_notificationsPage() async throws {
        let h = try fixtureHarness("json/notifications.json")
        let page = try await LiveNotificationsRepository(api: h.api, locale: h.locale).page(unreadOnly: true, limit: 10, offset: 20)
        #expect(!page.items.isEmpty)
        #expect(page.items.first?.kind == "fare_drop")
        let url = try #require(h.request?.url)
        #expect(url.path == "/api/notifications")
        #expect(url.query == "unread_only=true&limit=10&offset=20")
    }

    @Test func test_unreadCountAndMarkRead() async throws {
        let h = try Harness { request in
            request.url?.path.hasSuffix("unread-count") == true ? .init(json: #"{"count": 4}"#) : .init(json: #"{"updated": 2, "unread": 1}"#)
        }
        let repo = LiveNotificationsRepository(api: h.api, locale: h.locale)
        #expect(try await repo.unreadCount() == 4)
        #expect(try await repo.markRead(ids: [3, 4], all: false) == 1)
        #expect(try h.body(1)["ids"].array?.compactMap(\.int) == [3, 4])
        #expect(try await repo.markRead(ids: nil, all: true) == 1)
        #expect(try h.body(2)["all"].bool == true)
    }

    @Test func test_priceWatch422NoLivePriceCode() async throws {
        let h = try Harness { _ in
            .init(status: 422, json: #"{"detail":{"code":"no_live_price","message":"No live price for this trip"}}"#)
        }
        let repo = LiveWatchesRepository(api: h.api, locale: h.locale)
        do {
            _ = try await repo.createPrice(NewPriceWatch(kind: .trip, spec: .object(["destination": "Lisbon"])))
            Issue.record("expected a 422")
        } catch let error as APIError {
            guard case .client(let status, _, let code, _) = error else {
                Issue.record("expected .client, got \(error)")
                return
            }
            #expect(status == 422)
            #expect(code == "no_live_price")
            #expect(error.userFacingDetail == "No live price for this trip")
        }
        let body = try h.body()
        #expect(body["kind"].string == "trip")
        #expect(body["trip"]["destination"].string == "Lisbon")
    }

    @Test func test_devicesRegisterSendsPlatform() async throws {
        let h = try fixtureHarness("json/device.json")
        let repo = LiveDevicesRepository(api: h.api, locale: h.locale)
        let device = try await repo.register(DeviceRegistration(token: "abc123", platform: "ios", locale: "de-DE"))
        #expect(device.id == 12)
        #expect(device.platform == "ios")
        let body = try h.body()
        #expect(body["platform"].string == "ios")
        #expect(body["token"].string == "abc123")
        #expect(h.request?.url?.path == "/api/devices")
        #expect(h.request?.url?.query == nil, "a token never travels in a URL")
    }

    @Test func test_devicesListUnwrapsItemsAndUnregisterUsesBody() async throws {
        let h = try Harness { request in
            request.url?.path == "/api/devices/unregister"
                ? .init(status: 204)
                : .init(json: #"{"items":[{"id":1,"token":"…abc123","platform":"ios"},{"id":2,"platform":"android"}]}"#)
        }
        let repo = LiveDevicesRepository(api: h.api, locale: h.locale)
        #expect(try await repo.list().map(\.id) == [1, 2])
        try await repo.unregister(token: "FULLTOKEN")
        #expect(try h.body(1)["token"].string == "FULLTOKEN")
        #expect(h.stub.requests[1].url?.absoluteString.contains("FULLTOKEN") == false)
    }

    @Test func test_deviceRegistrationRejectedIsAnError() async throws {
        let h = try Harness { _ in .init(status: 422, json: #"{"detail":"platform must be android"}"#) }
        await #expect(throws: APIError.self) {
            _ = try await LiveDevicesRepository(api: h.api, locale: h.locale).register(DeviceRegistration(token: "t", platform: "ios"))
        }
    }

    @Test func test_matchUnwrapsWatchOrNil() async throws {
        let hit = try Harness { _ in .init(json: #"{"watch": {"id": 8, "origin_code": "BER"}}"#) }
        let query = WatchMatchQuery(kind: .flight, spec: .object(["origin": "BER", "destination": "LIS"]))
        let found = try await LiveWatchesRepository(api: hit.api, locale: hit.locale).match(query)
        #expect(found?["id"].int == 8)
        #expect(hit.request?.url?.path == "/api/fare-watches/match")
        #expect(try hit.body()["origin"].string == "BER", "a flight match sends the trip fields at the top level")

        let miss = try Harness { _ in .init(json: #"{"watch": null}"#) }
        #expect(try await LiveWatchesRepository(api: miss.api, locale: miss.locale).match(query) == nil)

        let hotel = try Harness { _ in .init(json: #"{"watch": null}"#) }
        _ = try await LiveWatchesRepository(api: hotel.api, locale: hotel.locale)
            .match(WatchMatchQuery(kind: .hotel, spec: .object(["name": "Lumen"]), planId: 2))
        #expect(hotel.request?.url?.path == "/api/price-watches/match")
        #expect(try hotel.body()["hotel"]["name"].string == "Lumen")
    }

    @Test func test_priceWatchesListAndPatchRoutes() async throws {
        let json = try Fixtures.string("json/price_watch.json")
        let h = try Harness { request in
            request.httpMethod == "GET" ? .init(json: "[\(json)]") : .init(json: json)
        }
        let repo = LiveWatchesRepository(api: h.api, locale: h.locale)
        #expect(try await repo.priceWatches(kind: .hotel).count == 1)
        #expect(h.request?.url?.query == "kind=hotel")
        let item = try await repo.patch(kind: .hotel, id: 4, WatchPatch(status: "paused"))
        guard case .price = item else {
            Issue.record("expected a price watch")
            return
        }
        #expect(h.stub.requests[1].httpMethod == "PATCH")
        #expect(h.stub.requests[1].url?.path == "/api/price-watches/4")
        try await repo.delete(kind: .hotel, id: 4)
        #expect(h.stub.requests[2].httpMethod == "DELETE")
    }

    @Test func test_plansRoundTrip() async throws {
        let h = try Harness { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("POST", "/api/plans/7/share"): .init(json: #"{"share_token":"abcDEF123"}"#)
            case ("DELETE", _): .init(json: #"{"success": true}"#)
            default: .init(json: "[]")
            }
        }
        let repo = LivePlansRepository(api: h.api, locale: h.locale)
        #expect(try await repo.list().isEmpty)
        #expect(try await repo.share(id: 7) == "abcDEF123")
        try await repo.delete(id: 7)
    }

    @Test func test_sharedPlanIsAnonymous() async throws {
        let h = try Harness(token: "tok") { _ in .init(json: #"{"name":"Tokyo","search_data":{},"selections":{}}"#) }
        let plan = try await LivePlansRepository(api: h.api, locale: h.locale).shared(token: "abcDEF123")
        #expect(plan.name == "Tokyo")
        #expect(h.request?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(h.request?.url?.path == "/api/share/abcDEF123")
    }

    @Test func test_aiBodiesGetLocale() async throws {
        let h = try Harness(language: .es) { _ in .init(json: #"{"destinations": []}"#) }
        _ = try await LiveDiscoverRepository(api: h.api, locale: h.locale).suggestions(DiscoverRequest(origin: "JFK"))
        #expect(try h.body()["locale"].string == "es")
        #expect(try h.body()["origin"].string == "JFK")

        let agents = LiveAgentsRepository(api: h.api, locale: h.locale)
        _ = try await agents.filtered(.hotels, request: TravelSearchRequest(destination: "Rome"), filters: .object(["num_beds": 2]))
        #expect(h.stub.requests[1].url?.path == "/api/hotels/filtered")
        #expect(try h.body(1)["locale"].string == "es")
        #expect(try h.body(1)["num_beds"].int == 2)
        #expect(try h.body(1)["destination"].string == "Rome")

        _ = try await agents.stressTest(itinerary: .object(["days": .array([])]), request: TravelSearchRequest(destination: "Rome"))
        #expect(try h.body(2)["itinerary"]["days"].array?.isEmpty == true)
        #expect(try h.body(2)["locale"].string == "es")

        _ = try await agents.layover(.object(["city": "Doha", "duration_hours": 6]))
        #expect(try h.body(3)["locale"].string == "es")

        _ = try await agents.layover(.object(["city": "Doha", "locale": "fr"]))
        #expect(try h.body(4)["locale"].string == "fr")

        _ = try await agents.fareCalendar(TravelSearchRequest(origin: "BER", destination: "LIS"))
        #expect(try h.body(5)["locale"].string == nil, "the fare calendar is not an AI call")
    }

    @Test func test_compareGetsLocaleAndNearbyLanguage() async throws {
        let h = try Harness(language: .fr) { request in
            request.url?.path == "/api/nearby" ? .init(json: #"{"sections": []}"#) : .init(json: "{}")
        }
        _ = try await LiveCompareRepository(api: h.api, locale: h.locale).summary(TravelSearchRequest(destination: "Rome"))
        #expect(try h.body()["locale"].string == "fr")
        _ = try? await LiveNearbyRepository(api: h.api, locale: h.locale).nearby(NearbyRequest(lat: 1, lng: 2, sections: true))
        #expect(try h.body(1)["language"].string == "fr")
        _ = try? await LiveNearbyRepository(api: h.api, locale: h.locale).nearby(NearbyRequest(lat: 1, lng: 2, language: "en"))
        #expect(try h.body(2)["language"].string == "en")
    }

    @Test func test_healthAndConfig404() async throws {
        let h = try Harness(token: nil) { request in
            request.url?.path == "/health"
                ? .init(json: #"{"status":"ok","serpapi_configured":true}"#)
                : .init(status: 404, json: #"{"detail":"Not Found"}"#)
        }
        let repo = LiveHealthRepository(api: h.api, locale: h.locale)
        #expect(try await repo.health().serpapiConfigured == true)
        #expect(try await repo.clientConfig() == nil)
        #expect(h.stub.requests.count == 2, "no retry")
    }

    @Test func test_configOtherErrorsStillThrow() async throws {
        let h = try Harness(token: nil) { _ in .init(status: 500, json: #"{"detail":"x"}"#) }
        await #expect(throws: APIError.self) { _ = try await LiveHealthRepository(api: h.api, locale: h.locale).clientConfig() }
    }

    @Test func test_preferencesAndEmail() async throws {
        let h = try Harness { request in
            request.url?.path == "/api/auth/email" ? .init(json: #"{"email":"a@b.co"}"#) : .init(json: #"{"username":"alice"}"#)
        }
        let repo = LivePreferencesRepository(api: h.api, locale: h.locale)
        #expect(try await repo.get().username == "alice")
        #expect(try await repo.setEmail("a@b.co") == "a@b.co")
        #expect(h.stub.requests[1].httpMethod == "PUT")
    }

    @Test func test_recentSearchesAndReference() async throws {
        let h = try Harness { request in
            switch request.url?.path ?? "" {
            case "/api/airports/search": .init(json: try! Fixtures.string("json/airports.json"))
            case "/api/recent-searches" where request.httpMethod == "POST": .init(status: 200, json: "{}")
            default: .init(json: try! Fixtures.string("json/recent_searches.json"))
            }
        }
        let recent = LiveRecentSearchesRepository(api: h.api, locale: h.locale)
        #expect(!(try await recent.list()).isEmpty)
        try await recent.record(.object(["destination": "Lisbon"]))
        try await LiveRecentSearchesRepository(api: h.api, locale: h.locale).delete(id: 3)
        let airports = try await LiveReferenceRepository(api: h.api, locale: h.locale).airports("tok", limit: 5)
        #expect(!airports.isEmpty)
        let url = try #require(h.stub.requests.last?.url)
        #expect(url.query == "q=tok&limit=5")
        #expect(h.stub.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func test_adminAndFeedback() async throws {
        let h = try Harness { _ in .init(json: "[]") }
        let admin = LiveAdminRepository(api: h.api, locale: h.locale)
        #expect(try await admin.users().isEmpty)
        #expect(try await admin.feedback(page: "results", category: nil, minRating: 2).isEmpty)
        #expect(h.stub.requests[1].url?.query == "page=results&min_rating=2")
        try await admin.deactivate("bob")
        try await admin.resetPassword("bob", newPassword: "newpass123")
        #expect(h.stub.requests[3].url?.path == "/api/admin/users/bob/reset-password")
        #expect(try h.body(3)["new_password"].string == "newpass123")
        try await LiveFeedbackRepository(api: h.api, locale: h.locale)
            .submit(FeedbackSubmission(page: "results", rating: 5, category: "praise"))
        #expect(h.stub.requests[4].url?.path == "/api/feedback")
    }

    @Test func test_importExtractAndResolve() async throws {
        let h = try Harness { request in
            request.url?.path == "/api/import/extract"
                ? .init(json: try! Fixtures.string("json/import_preview.json")) : .init(json: #"{"place": {}}"#)
        }
        let repo = LiveImportRepository(api: h.api, locale: h.locale)
        _ = try await repo.extract(LinkImportRequest(url: "https://example.com/list"))
        #expect(try h.body()["url"].string == "https://example.com/list")
        _ = try await repo.resolvePlace(ResolvePlaceRequest(name: "Cafe", city: "Lisbon"))
        #expect(h.stub.requests[1].url?.path == "/api/import/resolve-place")
    }

    @Test func test_liveCheckSendsKindAndWatchId() async throws {
        let h = try fixtureHarness("json/live_check.json")
        _ = try await LiveWatchesRepository(api: h.api, locale: h.locale).liveCheck(LiveCheckRequest(kind: .hotel, watchId: 4))
        #expect(try h.body()["kind"].string == "hotel")
        #expect(try h.body()["watch_id"].int == 4)
    }
}
