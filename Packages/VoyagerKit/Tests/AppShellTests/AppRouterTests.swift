import Foundation
import Testing
import VoyagerModel

@testable import AppShell

@MainActor
@Suite struct AppRouterTests {
    @Test func test_planDetailSelectsTripsAndPushes() {
        let router = AppRouter()
        router.open(.planDetail(id: 3))
        #expect(router.selectedTab == .trips)
        #expect(router.path(.trips) == [.planDetail(id: 3)])
    }

    @Test func test_eachTabKeepsItsOwnPath() {
        let router = AppRouter()
        router.open(.planDetail(id: 3))
        router.open(.notifications)
        router.open(.tab(.trips))
        #expect(router.path(.trips) == [.planDetail(id: 3)])
        #expect(router.path(.alerts) == [.notifications])
        #expect(router.selectedTab == .trips)
    }

    @Test func test_resultsPushOnExplore() {
        let router = AppRouter()
        router.open(.tab(.you))
        let request = TravelSearchRequest()
        router.open(.results(request))
        #expect(router.selectedTab == .explore)
        #expect(router.path(.explore) == [.results(request)])
    }

    @Test func test_exploreModeAndImportURL() throws {
        let router = AppRouter()
        router.open(.explore(.compare))
        #expect(router.exploreMode == .compare)
        let url = try #require(URL(string: "https://example.com/a"))
        router.open(.importLink(url))
        #expect(router.exploreMode == .link)
        #expect(router.importURL == url)
        #expect(router.selectedTab == .explore)
    }

    @Test func test_alertsRouteSetsFocus() {
        let router = AppRouter()
        router.open(.alerts(kind: .hotel, watchID: 9))
        #expect(router.selectedTab == .alerts)
        #expect(router.alertsFocus == AlertsFocus(kind: .hotel, watchID: 9))
    }

    @Test func test_presentationsDoNotChangeTab() {
        let router = AppRouter()
        router.open(.tab(.trips))
        router.open(.myPlan)
        router.open(.nearby)
        router.open(.share(token: "t"))
        #expect(router.selectedTab == .trips)
        #expect(router.myPlanPresented && router.nearbyPresented)
        #expect(router.sharedToken == "t")
        router.closeShare()
        #expect(router.sharedToken == nil)
    }

    @Test func test_youTabRoutes() {
        let router = AppRouter()
        router.open(.preferences)
        #expect(router.selectedTab == .you)
        #expect(router.path(.you) == [.preferences])
        router.open(.settings)
        #expect(router.path(.you).isEmpty)
    }

    @Test func test_popRemovesLastRoute() {
        let router = AppRouter()
        router.open(.preferences)
        router.open(.tasteProfile)
        router.pop(.you)
        #expect(router.path(.you) == [.preferences])
    }
}
