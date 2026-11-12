import AuthCore
import Networking
import SectionsUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureTrips

@MainActor
final class PlanDetailModelTests: XCTestCase {
    private func make(files: MemoryFileStore = MemoryFileStore()) async -> (PlanDetailModel, AppEnvironment, FakeRepositories) {
        let fakes = FakeRepositories()
        fakes.plans.onGet.returns(TripsFixtures.savedPlan)
        let env = AppEnvironment.fake(fakes: fakes)
        let model = PlanDetailModel(env: env, planID: 2, files: files)
        await model.load()
        return (model, env, fakes)
    }

    func test_blocksGroupPickedItemsBySection() {
        let blocks = PlanDetailModel.blocks(for: TripsFixtures.savedPlan.selections)
        XCTAssertEqual(blocks.map(\.section), [.flights, .hotels, .activities, .tips])
        XCTAssertEqual(blocks[1].items.first?.name, "Park Hotel Tokyo")
        XCTAssertEqual(blocks[2].items.count, 2)
    }

    func test_blocksOfEmptySelectionsAreEmpty() {
        XCTAssertTrue(PlanDetailModel.blocks(for: .null).isEmpty)
        XCTAssertNil(PlanDetailModel.itinerary(in: ["itinerary": ["days": []]]))
    }

    func test_openInMyPlanLoadsAndRoutes() async {
        let (model, env, _) = await make()
        model.openInMyPlan()
        XCTAssertEqual(env.plan.savedPlanID, 2)
        XCTAssertEqual(env.plan.planName, "Tokyo food trip")
        XCTAssertEqual(env.recordedRoutes, [.myPlan])
    }

    func test_shareBuildsPublicLink() async {
        let (model, _, fakes) = await make()
        fakes.plans.onShare.returns("tok123")
        await model.share()
        XCTAssertEqual(model.shareURL?.absoluteString, "https://fake.voyager.test/share/tok123")
        XCTAssertFalse(model.shareFailed)
    }

    func test_deleteNeedsConfirmationThenLeaves() async {
        let (model, env, fakes) = await make()
        env.plan.load(TripsFixtures.savedPlan)
        model.requestDelete()
        XCTAssertTrue(model.confirmingDelete)
        XCTAssertEqual(fakes.plans.onDelete.callCount, 0)
        let removed = await model.confirmDelete()
        XCTAssertTrue(removed)
        XCTAssertTrue(model.deleted)
        XCTAssertEqual(fakes.plans.onDelete.calls, [2])
        XCTAssertNil(env.plan.savedPlanID)
    }

    func test_offlineOpensCachedPlan() async {
        let files = MemoryFileStore()
        _ = await make(files: files) // a successful load caches the plan
        let (model, _, fakes) = await {
            let fakes = FakeRepositories()
            fakes.plans.onGet.fails(APIError.network)
            let env = AppEnvironment.fake(fakes: fakes)
            return (PlanDetailModel(env: env, planID: 2, files: files), env, fakes)
        }()
        _ = fakes
        await model.load()
        XCTAssertEqual(model.plan?.name, "Tokyo food trip")
        XCTAssertTrue(model.isOffline)
    }

    func test_offlineWithoutCacheFails() async {
        let fakes = FakeRepositories()
        fakes.plans.onGet.fails(APIError.network)
        let model = PlanDetailModel(env: AppEnvironment.fake(fakes: fakes), planID: 2, files: MemoryFileStore())
        await model.load()
        XCTAssertNil(model.plan)
        XCTAssertFalse(model.isOffline)
    }

    func test_otherUsersCachedPlanIsNotShown() async {
        let files = MemoryFileStore()
        _ = await make(files: files)
        let fakes = FakeRepositories()
        fakes.plans.onGet.fails(APIError.network)
        let env = AppEnvironment.fake(user: User(username: "bob"), fakes: fakes)
        let model = PlanDetailModel(env: env, planID: 2, files: files)
        await model.load()
        XCTAssertNil(model.plan)
    }
}
