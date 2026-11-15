import Foundation
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureShare

@MainActor
struct SharedViewerTests {
    private func model(_ plan: SharedPlan, token: String = "tok12345") async -> (SharedPlanModel, FakeRepositories, AppEnvironment) {
        let fakes = FakeRepositories()
        fakes.plans.onShared.returns(plan)
        let env = AppEnvironment.fake(user: nil, fakes: fakes)
        let model = SharedPlanModel(env: env, token: token)
        await model.load()
        return (model, fakes, env)
    }

    private let recap = SharedPlan(
        name: "Japan trip", kind: "recap", ownerName: nil,
        card: SharedCard(
            headline: "My trip to Japan: recap",
            stats: [.init(key: "places", count: 9), .init(key: "activities", count: 4), .init(key: "zero", count: 0)],
            destination: "Japan", period: "2026-05"))

    @Test func test_recapCardRenders() async {
        let (model, _, _) = await model(recap)
        #expect(model.presentation == .recap)
        #expect(model.isCard)
        #expect(model.sections.isEmpty)
        #expect(model.cardHeadline == "My trip to Japan: recap")
        let stats = SharedCardBody.visibleStats(model.plan?.card ?? SharedCard())
        #expect(stats.map(\.count) == [9, 4])
    }

    @Test func test_savingsCardRenders() async {
        let savings = SharedPlan(
            name: "Price alerts", kind: "savings",
            card: SharedCard(
                headline: "Caught drops worth $412",
                stats: [.init(key: "drops_caught", count: 3), .init(key: "targets_hit", count: 1)]))
        let (model, _, _) = await model(savings)
        #expect(model.presentation == .savings)
        #expect(model.cardHeadline == "Caught drops worth $412")
        #expect(SharedCardBody.visibleStats(model.plan?.card ?? SharedCard()).count == 2)
    }

    @Test func test_unknownStatKeysAreIgnored() {
        let card = SharedCard(stats: [.init(key: "future_thing", count: 5), .init(key: "hotels", count: 2)])
        #expect(SharedCardBody.visibleStats(card).map(\.count) == [2])
    }

    @Test func test_unknownKindOffersBrowser() async {
        let quiz = SharedPlan(name: "Quiz", kind: "quiz", card: SharedCard(headline: "Flags quiz: 4/5"))
        let (model, _, _) = await model(quiz)
        #expect(model.presentation == .unknown)
        #expect(model.sections.isEmpty)
        #expect(model.cardHeadline == "Flags quiz: 4/5")
        #expect(model.browserURL?.absoluteString == "https://fake.voyager.test/share/tok12345")
        // A kind nobody has heard of, without a card, still shows the share's name.
        let (later, _, _) = await model(SharedPlan(name: "Later", kind: "hologram"))
        #expect(later.presentation == .unknown)
        #expect(later.cardHeadline == "Later")
        // A card kind without its card is not trusted to render.
        let (bare, _, _) = await model(SharedPlan(name: "Bare", kind: "recap"))
        #expect(bare.presentation == .unknown)
    }

    @Test func test_legacyTokenUnchanged() async {
        let (model, _, _) = await model(Fixtures.decode(SharedPlan.self, "shared_plan"))
        #expect(model.presentation == .plan)
        #expect(model.isCard == false)
        #expect(model.sections.map(\.id.rawValue) == ["activities"])
        #expect(model.inspiredBy?.label == "48 hours in Tokyo")
    }

    @Test func test_ownerNameOnlyWhenPresent() async {
        var named = recap
        named.ownerName = "Amy"
        let (withName, _, _) = await model(named)
        #expect(withName.ownerName == "Amy")
        let (without, _, _) = await model(recap)
        #expect(without.ownerName == nil)
        var blank = recap
        blank.ownerName = "  "
        let (empty, _, _) = await model(blank)
        #expect(empty.ownerName == nil)
    }

    @Test func test_planOwnTripOpensExplore() async {
        let (model, _, env) = await model(recap)
        model.planOwnTrip()
        #expect(env.recordedRoutes == [.tab(.explore)])
    }

    @Test func test_remixIsPlanOnly() async {
        let (model, _, env) = await model(recap)
        model.remix()
        #expect(env.recordedRoutes.isEmpty)
        #expect(model.needsSignIn == false)
    }
}
