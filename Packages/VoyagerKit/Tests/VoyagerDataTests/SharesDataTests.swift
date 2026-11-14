import Foundation
import Networking
import Testing
import VoyagerModel

@testable import VoyagerData

struct SharesDataTests {
    @Test func test_routes() {
        let create = Endpoints.sharesCreate(ShareRequest(kind: .plan, planID: 12))
        #expect(create.method == .post && create.path == "/api/shares" && create.auth == .required)
        let list = Endpoints.sharesList()
        #expect(list.method == .get && list.path == "/api/shares")
        let revoke = Endpoints.sharesRevoke(token: "abc_123-X")
        #expect(revoke.method == .delete && revoke.path == "/api/shares/abc_123-X" && revoke.auth == .required)
    }

    @Test func test_tokenCannotEscapeItsPathSegment() {
        #expect(Endpoints.sharesRevoke(token: "../plans/1").path == "/api/shares/..%2Fplans%2F1")
        #expect(Endpoints.sharesRevoke(token: "a?b#c d").path == "/api/shares/a%3Fb%23c%20d")
    }

    @Test func test_telemetryNameCarriesNoToken() {
        #expect(Endpoints.sharesRevoke(token: "secrettoken99").telemetryName == "/api/shares/:token")
        #expect(!Endpoints.sharesCreate(ShareRequest(kind: .plan, planID: 4242)).telemetryName.contains("4242"))
    }

    @Test func test_createSendsPrivateOptionsAndTheAppLanguage() async throws {
        let h = try Harness(language: .de) { _ in
            .init(json: """
            {"token": "t1", "kind": "plan", "url": "https://h/share/t1", "plan_id": 3,
             "card_url": {"link": "https://h/c?size=link", "story": "https://h/c?size=story"},
             "options": {"dates": "hidden", "show_origin": false, "show_name": false}, "created_at": "2026-11-14T10:00:00Z"}
            """)
        }
        let repo = LiveSharesRepository(api: h.api, locale: h.locale)
        let share = try await repo.create(ShareRequest(kind: .plan, planID: 3))
        #expect(share.token == "t1" && share.cardStoryURL == "https://h/c?size=story")
        let body = try h.body()
        #expect(body["locale"].string == "de" && body["options"]["dates"].string == "hidden" && body["plan_id"].int == 3)
        #expect(h.request?.httpMethod == "POST" && h.request?.url?.path == "/api/shares")
    }

    @Test func test_revokeIs204AndListDecodes() async throws {
        let h = try Harness { request in
            request.httpMethod == "DELETE" ? .init(status: 204) : .init(json: #"{"shares": [], "legacy_plan_shares": []}"#)
        }
        let repo = LiveSharesRepository(api: h.api, locale: h.locale)
        try await repo.revoke(token: "t1")
        #expect(h.request?.httpMethod == "DELETE" && h.request?.url?.path == "/api/shares/t1")
        #expect(try await repo.list() == ShareList())
    }
}
