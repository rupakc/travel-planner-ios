import Foundation
import Testing
@testable import VoyagerModel

struct SharesModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func object(_ request: ShareRequest) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
    }

    @Test func test_privateDefaults() throws {
        let options = ShareOptions()
        #expect(options.dates == .hidden && !options.showOrigin && !options.showName)
        // A request that names no options sends the private ones.
        let body = try object(ShareRequest(kind: .plan, planID: 12))
        #expect(body["options"]["dates"].string == "hidden")
        #expect(body["options"]["show_origin"].bool == false && body["options"]["show_name"].bool == false)
        #expect(body["kind"].string == "plan" && body["plan_id"].int == 12)
        // Unreadable options from the server read as private, never as a wider setting.
        let odd = try decode(ShareOptions.self, #"{"dates": "forever", "show_origin": "maybe", "show_name": null}"#)
        #expect(odd == ShareOptions())
    }

    @Test func test_requestFieldsPerKind() throws {
        let savings = try object(ShareRequest(target: .savings))
        #expect(savings["plan_id"].isNull && savings["session_id"].isNull && savings["kind"].string == "savings")
        let quiz = try object(ShareRequest(target: .quiz(sessionID: "s-1")))
        #expect(quiz["session_id"].string == "s-1" && quiz["plan_id"].isNull)
        let status = try object(ShareRequest(target: .status(planID: nil)))
        #expect(status["kind"].string == "status" && status["plan_id"].isNull)
        let recap = try object(ShareRequest(target: .recap(planID: 4), options: ShareOptions(dates: .month, showName: true), locale: "de"))
        #expect(recap["plan_id"].int == 4 && recap["options"]["dates"].string == "month" && recap["locale"].string == "de")
        #expect(ShareTarget.plan(id: 9).planID == 9 && ShareTarget.savings.planID == nil)
    }

    @Test func test_createAnswer() throws {
        let share = try decode(Share.self, """
        {"token": "abc", "kind": "plan", "plan_id": 12, "url": "https://host/share/abc",
         "card_url": {"link": "https://host/api/share/abc/card.png?size=link", "story": "https://host/api/share/abc/card.png?size=story"},
         "options": {"dates": "month", "show_origin": true, "show_name": false}, "created_at": "2026-11-14T10:00:00Z", "extra": 1}
        """)
        #expect(share.token == "abc" && share.kind == .plan && share.planID == 12)
        #expect(share.cardStoryURL?.hasSuffix("size=story") == true && share.cardLinkURL?.hasSuffix("size=link") == true)
        #expect(share.options == ShareOptions(dates: .month, showOrigin: true, showName: false))
        #expect(share.linkURL?.host == "host")
    }

    @Test func test_unknownKindIsPlainLink() throws {
        let share = try decode(Share.self, #"{"token": "t1", "kind": "podcast", "url": "https://host/share/t1"}"#)
        #expect(share.kind == .unknown("podcast") && !share.kind.isKnown)
        #expect(share.kind.telemetryValue == nil)
        #expect(share.kind.rawValue == "podcast")
        #expect(share.linkURL != nil && share.cardLinkURL == nil)
        for known in [ShareKind.plan, .recap, .savings, .quiz, .status] { #expect(known.telemetryValue == known.rawValue) }
    }

    @Test func test_listKeepsGoodRowsAndLegacyLinks() throws {
        let list = try decode(ShareList.self, """
        {"shares": [{"token": "a", "kind": "recap", "title": "Lisbon", "url": "https://h/share/a", "plan_id": 3},
                    {"kind": "plan"},
                    {"token": "b", "kind": "savings", "title": "Price alerts", "url": "https://h/share/b", "plan_id": null}],
         "legacy_plan_shares": [{"plan_id": 7, "name": "Old trip", "url": "https://h/share/zz"}, {"name": "broken"}]}
        """)
        #expect(list.shares.map(\.token) == ["a", "b"])
        #expect(list.shares[1].planID == nil && list.shares[0].title == "Lisbon")
        #expect(list.legacyPlanShares == [LegacyPlanShare(planID: 7, name: "Old trip", url: "https://h/share/zz")])
        #expect(try decode(ShareList.self, "{}") == ShareList())
    }
}
