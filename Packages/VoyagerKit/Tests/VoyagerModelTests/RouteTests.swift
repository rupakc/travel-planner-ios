import Foundation
import Testing
@testable import VoyagerModel

@Suite struct RouteTests {
    @Test func test_templatesNeverContainIDs() {
        let plan = TelemetryRouteName.template(for: .planDetail(id: 42))
        #expect(plan == "/plans/:id")
        #expect(!plan.contains("42"))
        let share = TelemetryRouteName.template(for: .share(token: "abc"))
        #expect(share == "/share/:token")
        #expect(!share.contains("abc"))
        #expect(TelemetryRouteName.template(for: .alerts(kind: .hotel, watchID: 9)) == "/alerts/:id")
        #expect(TelemetryRouteName.template(for: .alerts(kind: nil, watchID: nil)) == "/alerts")
        let link = TelemetryRouteName.template(for: .importLink(URL(string: "https://secret.example/x")))
        #expect(link == "/import")
        #expect(TelemetryRouteName.template(for: .results(TravelSearchRequest(destination: "Secretville"))) == "/results")
    }

    @Test func test_everyTemplateIsSlashPrefixedAndTokenSafe() {
        let routes: [Route] = AppTab.allCases.map { .tab($0) } + ExploreMode.allCases.map { .explore($0) } + [
            .myPlan, .notifications, .nearby, .settings, .preferences, .tasteProfile, .admin,
            .changePassword(forced: true), .onboarding(fromSettings: false),
        ]
        for route in routes {
            let template = TelemetryRouteName.template(for: route)
            #expect(template.hasPrefix("/"))
            #expect(template.allSatisfy { $0.isLetter || $0 == "/" || $0 == "-" || $0 == ":" })
        }
    }

    @Test func test_routeIsHashable() {
        #expect(Route.planDetail(id: 1) != Route.planDetail(id: 2))
        #expect(Set([Route.myPlan, Route.myPlan]).count == 1)
    }
}

@Suite struct RoutePhase3to6Tests {
    @Test func test_phase3to6TemplatesAreFixedStrings() {
        let routes: [Route] = [
            .shareSheet(.plan(id: 7)), .shareSheet(.quiz(sessionID: "s-secret")), .myShares, .openShare(token: "tok-secret"),
            .notificationSettings, .alertPrefs, .priceStory(kind: .flight, id: 9), .tripToday(planID: 12),
            .profile(handle: "amy_secret"), .profileEditor, .ideaDetail(id: "i-secret"), .ideas, .play,
            .quiz(sessionID: "s-secret"), .h2h(id: "m-secret"),
        ]
        for route in routes {
            let template = TelemetryRouteName.template(for: route)
            #expect(template.hasPrefix("/") && template != "/unknown")
            #expect(template.allSatisfy { $0.isLetter || $0 == "/" || $0 == "-" || $0 == ":" })
            #expect(!template.contains("secret"))
        }
    }
}
