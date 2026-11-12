import Foundation
import L10n
import Networking
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureShare

@MainActor
struct SharedPlanModelTests {
    private func plan() -> SharedPlan { Fixtures.decode(SharedPlan.self, "shared_plan") }

    @Test func test_signedOutCanView() async {
        let fakes = FakeRepositories()
        fakes.plans.onShared.returns(plan())
        let env = AppEnvironment.fake(user: nil, fakes: fakes)
        let model = SharedPlanModel(env: env, token: "abc12345")
        await model.load()

        #expect(model.isSignedIn == false)
        #expect(model.plan?.name == "Tokyo")
        #expect(fakes.plans.onShared.lastCall == "abc12345")
        #expect(model.destination == "Tokyo")
        #expect(model.sections.map(\.id.rawValue) == ["activities"])
        let inspired = model.inspiredBy
        #expect(inspired?.label == "48 hours in Tokyo")
        #expect(inspired?.url?.absoluteString == "https://blog.example/tokyo")
    }

    @Test func test_404Copy() async {
        let fakes = FakeRepositories()
        fakes.plans.onShared.fails(APIError.notFound("Shared plan not found"))
        let model = SharedPlanModel(env: AppEnvironment.fake(user: nil, fakes: fakes), token: "gone")
        await model.load()

        #expect(model.state == .notFound)
        // The web's link-not-found copy (`misc:share.unavailable*`).
        #expect(L10n.text(K.misc.share.unavailableTitle) == "This shared trip isn't available")
        #expect(L10n.text(K.misc.share.unavailableBody) == "The link may have been revoked or mistyped.")
    }

    @Test func test_otherFailureIsNotA404() async {
        let fakes = FakeRepositories()
        fakes.plans.onShared.fails(APIError.network)
        let model = SharedPlanModel(env: AppEnvironment.fake(user: nil, fakes: fakes), token: "t")
        await model.load()
        guard case .failed = model.state else {
            Issue.record("expected failed")
            return
        }
    }

    @Test func test_remixRequiresSignIn() async {
        let fakes = FakeRepositories()
        fakes.plans.onShared.returns(plan())

        let signedOut = AppEnvironment.fake(user: nil, fakes: fakes)
        let outModel = SharedPlanModel(env: signedOut, token: "t")
        await outModel.load()
        outModel.remix()
        #expect(outModel.needsSignIn)
        #expect(signedOut.recordedRoutes.isEmpty)
        #expect(signedOut.plan.savedPlanID == nil)
        #expect(signedOut.plan.selections["activities"].array?.isEmpty == true)

        let signedIn = AppEnvironment.fake(fakes: fakes)
        let inModel = SharedPlanModel(env: signedIn, token: "t")
        await inModel.load()
        inModel.remix()
        #expect(inModel.needsSignIn == false)
        #expect(signedIn.recordedRoutes == [.myPlan])
        #expect(signedIn.plan.selections["activities"].array?.count == 1)
        #expect(signedIn.plan.savedPlanID == nil)  // a copy, never the sharer's plan
        #expect(signedIn.plan.planName == "Tokyo")
    }

    @Test func test_phase4FieldsDecode() throws {
        let json = """
            {"name":"Price alerts","kind":"savings","owner_name":"Amy","search_data":{},"selections":{},
             "card":{"headline":"Caught drops worth $412","stats":[{"key":"drops_caught","count":3}],"period":"2026-05"}}
            """
        let plan = try JSONDecoder().decode(SharedPlan.self, from: Data(json.utf8))
        #expect(plan.kind == "savings")
        #expect(plan.ownerName == "Amy")
        #expect(plan.card?.stats == [.init(key: "drops_caught", count: 3)])
        #expect(plan.card?.period == "2026-05")
        // A legacy answer has none of them.
        #expect(Fixtures.decode(SharedPlan.self, "shared_plan").card == nil)
    }

    @Test func test_untrustedSourceURLHasNoLink() async {
        let fakes = FakeRepositories()
        var shared = plan()
        shared.searchData = ["import_source": ["url": "javascript:alert(1)", "title": "x"]]
        fakes.plans.onShared.returns(shared)
        let model = SharedPlanModel(env: AppEnvironment.fake(user: nil, fakes: fakes), token: "t")
        await model.load()
        #expect(model.inspiredBy?.url == nil)
        #expect(model.inspiredBy?.label == "x")
    }
}
