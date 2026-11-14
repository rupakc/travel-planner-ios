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

    // MARK: - Itinerary editing (Task 29)

    private static let plan: SavedPlan = {
        var selections = TripsFixtures.savedPlan.selections
        selections = .object(
            (selections.object ?? [:]).merging([
                "itinerary": ["days": [["day_number": 1, "slots": [["time_of_day": "morning", "activity": "Senso-ji"]]]]]
            ]) { _, new in new })
        return SavedPlan(id: 2, name: "Tokyo food trip", searchData: TripsFixtures.near.searchData, selections: selections)
    }()

    private func makeEditable() async -> (PlanDetailModel, AppEnvironment, FakeRepositories) {
        let fakes = FakeRepositories()
        fakes.plans.onGet.returns(Self.plan)
        let env = AppEnvironment.fake(fakes: fakes)
        let model = PlanDetailModel(env: env, planID: 2, files: MemoryFileStore())
        await model.load()
        return (model, env, fakes)
    }

    func test_editsWaitInADraftUntilSaved() async {
        let (model, _, fakes) = await makeEditable()
        XCTAssertFalse(model.hasUnsavedEdits)
        var edited = model.selections
        edited = .object((edited.object ?? [:]).merging(["itinerary_notes": ["1-morning": "Bring cash"]]) { _, new in new })
        model.setDraft(edited)
        XCTAssertTrue(model.hasUnsavedEdits)
        XCTAssertEqual(model.selections["itinerary_notes"]["1-morning"].string, "Bring cash")
        XCTAssertEqual(model.plan?.selections["itinerary_notes"]["1-morning"].string, nil)
        XCTAssertEqual(fakes.plans.onUpdate.callCount, 0)

        var saved = Self.plan
        saved.selections = edited
        fakes.plans.onUpdate.returns(saved)
        await model.saveEdits()
        XCTAssertEqual(fakes.plans.onUpdate.lastCall?.id, 2)
        XCTAssertEqual(fakes.plans.onUpdate.lastCall?.update.selections, edited)
        XCTAssertFalse(model.hasUnsavedEdits)
        XCTAssertTrue(model.editsSaved)
        XCTAssertEqual(model.plan?.selections["itinerary_notes"]["1-morning"].string, "Bring cash")
    }

    func test_failedSaveKeepsTheDraft() async {
        let (model, _, fakes) = await makeEditable()
        model.setDraft(.object((model.selections.object ?? [:]).merging(["itinerary_slots": [["key": "1-morning"]]]) { _, new in new }))
        fakes.plans.onUpdate.fails(APIError.network)
        await model.saveEdits()
        XCTAssertTrue(model.saveEditsFailed)
        XCTAssertTrue(model.hasUnsavedEdits)
    }

    func test_undoingEveryEditDropsTheDraft() async {
        let (model, _, _) = await makeEditable()
        model.setDraft(.object((model.selections.object ?? [:]).merging(["itinerary_notes": ["1-morning": "x"]]) { _, new in new }))
        XCTAssertTrue(model.hasUnsavedEdits)
        guard let loaded = model.plan?.selections else { return XCTFail("the plan did not load") }
        model.setDraft(loaded)
        XCTAssertNil(model.draft, "draft \(String(describing: model.draft)) vs loaded \(loaded)")
        XCTAssertFalse(model.hasUnsavedEdits)
    }
}
