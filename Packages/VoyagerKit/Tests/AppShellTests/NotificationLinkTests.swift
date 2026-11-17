import Domain
import Foundation
import NotificationsCore
import Testing
import VoyagerModel

@testable import AppShell

/// A server notification `link` is mapped only through the deep-link allow-list (R8).
@Suite struct NotificationLinkTests {
    init() { NotificationLinks.install { DeepLinks.route(forNotificationLink: $0) } }

    private func route(kind: String, link: String?, plan: Int? = nil) -> Route? {
        NotificationTarget.route(kind: kind, planID: plan, link: link)
    }

    @Test func test_linkAllowListed() {
        #expect(route(kind: "social_idea_saved", link: "/feed/abc123") == .ideaDetail(id: "abc123"))
        #expect(route(kind: "social_new_follower", link: "/u/maria") == .profile(handle: "maria"))
        #expect(route(kind: "social_new_follower", link: "/feed") == .ideas)
        #expect(route(kind: "quiz_h2h_invite", link: "/play/h2h/m42") == .h2h(id: "m42"))
        #expect(route(kind: "quiz_daily", link: "/play") == .play)
    }

    @Test func test_aLinkIsNeverOpenedRaw() {
        for link in ["https://evil.example/feed", "//evil.example/feed", "javascript:alert(1)", "/unknown/path", "/feed/../x", ""] {
            // Social rows fall back to the Ideas tab, quiz rows to the Play tab; none opens the link itself.
            #expect(route(kind: "social_new_follower", link: link) == .ideas)
            #expect(route(kind: "quiz_h2h_result", link: link) == .play)
        }
    }

    @Test func test_tapPayloadFollowsTheAllowListedLink() {
        let info: [AnyHashable: Any] = ["kind": "social_idea_saved", "link": "/feed/idea9", "category": "social"]
        #expect(NotificationRouting.route(userInfo: info) == .ideaDetail(id: "idea9"))
    }

    @Test func test_socialKindsRoute() {
        let cases: [(kind: String, link: String?, route: Route)] = [
            ("social_idea_saved", "/feed", .ideas), ("social_idea_liked", "/feed/i7", .ideaDetail(id: "i7")),
            ("social_idea_comment", "/feed/i7", .ideaDetail(id: "i7")), ("social_new_follower", "/feed", .ideas),
            ("social_new_follower", nil, .ideas),
        ]
        for item in cases {
            #expect(route(kind: item.kind, link: item.link) == item.route)
            // A hidden game changes nothing for the social kinds.
            #expect(
                NotificationTarget.route(kind: item.kind, planID: nil, link: item.link, playAvailable: false) == item.route)
        }
        let info: [AnyHashable: Any] = ["kind": "social_idea_comment", "link": "/feed/idea3"]
        #expect(NotificationRouting.route(userInfo: info, playAvailable: false) == .ideaDetail(id: "idea3"))
    }

    @Test func test_quizKindsNeverForHiddenGame() {
        for kind in ["quiz_h2h_invite", "quiz_h2h_result", "quiz_daily"] {
            #expect(NotificationTarget.route(kind: kind, planID: nil, link: "/play/h2h/m1", playAvailable: true) == .h2h(id: "m1"))
            #expect(NotificationTarget.route(kind: kind, planID: nil, link: "/play/h2h/m1", playAvailable: false) == .notifications)
            #expect(NotificationTarget.route(kind: kind, planID: nil, link: nil, playAvailable: false) == .notifications)
            let info: [AnyHashable: Any] = ["kind": kind, "link": "/play/h2h/m1"]
            #expect(NotificationRouting.route(userInfo: info, playAvailable: false) == .notifications)
        }
        // A link into Play never opens it for a hidden-game account, whatever the kind.
        #expect(NotificationTarget.route(kind: "social_new_follower", planID: nil, link: "/play", playAvailable: false) == .notifications)
    }

    @Test func test_tripKindsIgnoreTheLinkAndUsePlanID() {
        #expect(route(kind: "trip_t7", link: "/feed", plan: 4) == .tripToday(planID: 4))
    }
}
