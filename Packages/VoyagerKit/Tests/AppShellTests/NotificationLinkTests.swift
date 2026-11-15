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

    @Test func test_tripKindsIgnoreTheLinkAndUsePlanID() {
        #expect(route(kind: "trip_t7", link: "/feed", plan: 4) == .tripToday(planID: 4))
    }
}
