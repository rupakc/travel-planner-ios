import AuthCore
import Networking
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureTrips

@MainActor
final class TripsModelTests: XCTestCase {
    private func make(
        plans: [PlanSummary] = TripsFixtures.all, files: MemoryFileStore = MemoryFileStore()
    ) -> (TripsModel, AppEnvironment, FakeRepositories, MemoryFileStore) {
        let fakes = FakeRepositories()
        fakes.plans.onList.returns(plans)
        let env = AppEnvironment.fake(fakes: fakes)
        return (TripsFixtures.model(env, files: files), env, fakes, files)
    }

    func test_upcomingPickedByNearestFutureDate() async {
        let (model, _, _, _) = make()
        await model.load()
        XCTAssertEqual(model.upcoming?.id, TripsFixtures.near.id)
    }

    func test_upcomingIgnoresPastAndUndated() {
        let picked = TripsModel.upcoming(
            in: [TripsFixtures.past, TripsFixtures.undated], now: TripsFixtures.now, calendar: TripsFixtures.calendar)
        XCTAssertNil(picked)
    }

    func test_upcomingIncludesToday() {
        let today = TripsFixtures.plan(9, "Today", from: "2026-11-12", to: "2026-11-14")
        let picked = TripsModel.upcoming(
            in: [TripsFixtures.far, today], now: TripsFixtures.now, calendar: TripsFixtures.calendar)
        XCTAssertEqual(picked?.id, 9)
    }

    func test_offlineShowsCacheAndBanner() async throws {
        let seeded = PlansCache(username: User.sample.username, plans: [TripsFixtures.near, TripsFixtures.far])
        let files = MemoryFileStore(files: [PlansCache.path: try JSONEncoder().encode(seeded)])
        let (model, _, fakes, _) = make(files: files)
        fakes.plans.onList.fails(APIError.network)
        await model.load()
        XCTAssertEqual(model.plans.map(\.id), [2, 3])
        XCTAssertTrue(model.isOffline)
        XCTAssertFalse(model.failed)
    }

    func test_failureWithoutCacheIsAnError() async {
        let (model, _, fakes, _) = make()
        fakes.plans.onList.fails(APIError.network)
        await model.load()
        XCTAssertTrue(model.plans.isEmpty)
        XCTAssertTrue(model.failed)
        XCTAssertFalse(model.isOffline)
    }

    func test_successfulRefreshWritesCacheAndClearsBanner() async throws {
        let (model, _, _, files) = make()
        await model.load()
        XCTAssertFalse(model.isOffline)
        let data = try XCTUnwrap(files.files[PlansCache.path])
        let cache = try JSONDecoder().decode(PlansCache.self, from: data)
        XCTAssertEqual(cache.username, User.sample.username)
        XCTAssertEqual(cache.plans.map(\.id), TripsFixtures.all.map(\.id))
    }

    func test_anotherUsersCacheIsIgnored() async throws {
        let seeded = PlansCache(username: "someone-else", plans: [TripsFixtures.near])
        let files = MemoryFileStore(files: [PlansCache.path: try JSONEncoder().encode(seeded)])
        let (model, _, fakes, _) = make(files: files)
        fakes.plans.onList.fails(APIError.network)
        await model.load()
        XCTAssertTrue(model.plans.isEmpty)
        XCTAssertTrue(model.failed)
    }

    func test_deleteRemovesAfterConfirm() async {
        let (model, _, fakes, files) = make()
        await model.load()
        model.requestDelete(TripsFixtures.near)
        XCTAssertEqual(fakes.plans.onDelete.callCount, 0, "nothing is deleted before the confirmation")
        XCTAssertEqual(model.plans.count, 4)
        let removed = await model.confirmDelete()
        XCTAssertTrue(removed)
        XCTAssertEqual(fakes.plans.onDelete.calls, [2])
        XCTAssertFalse(model.plans.contains { $0.id == 2 })
        XCTAssertNil(model.pendingDelete)
        let cache = try? JSONDecoder().decode(PlansCache.self, from: files.files[PlansCache.path] ?? Data())
        XCTAssertEqual(cache?.plans.contains { $0.id == 2 }, false)
    }

    func test_cancelledDeleteKeepsThePlan() async {
        let (model, _, fakes, _) = make()
        await model.load()
        model.requestDelete(TripsFixtures.near)
        model.cancelDelete()
        let removed = await model.confirmDelete()
        XCTAssertFalse(removed)
        XCTAssertEqual(fakes.plans.onDelete.callCount, 0)
        XCTAssertEqual(model.plans.count, 4)
    }

    func test_failedDeleteKeepsThePlan() async {
        let (model, _, fakes, _) = make()
        await model.load()
        fakes.plans.onDelete.fails(APIError.network)
        model.requestDelete(TripsFixtures.near)
        let removed = await model.confirmDelete()
        XCTAssertFalse(removed)
        XCTAssertTrue(model.deleteFailed)
        XCTAssertEqual(model.plans.count, 4)
    }

    func test_searchAndFilter() async {
        let (model, _, _, _) = make()
        await model.load()
        model.query = "tokyo"
        XCTAssertEqual(model.visiblePlans.map(\.id), [2])
        model.query = ""
        model.filter = .upcoming
        XCTAssertEqual(Set(model.visiblePlans.map(\.id)), [2, 3])
        model.filter = .past
        XCTAssertEqual(model.visiblePlans.map(\.id), [1])
        model.filter = .all
        XCTAssertEqual(model.visiblePlans.count, 4)
    }
}
