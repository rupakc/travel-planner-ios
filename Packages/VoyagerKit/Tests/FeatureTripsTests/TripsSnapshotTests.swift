import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureTrips

@MainActor
final class TripsSnapshotTests: XCTestCase {
    private static let configs: [SnapshotConfig] = [.phoneLight, .phoneDark, .padLight, .padDark]

    private func env(plans: [PlanSummary]) -> (AppEnvironment, FakeRepositories) {
        let fakes = FakeRepositories()
        fakes.plans.onList.returns(plans)
        fakes.plans.onGet.returns(TripsFixtures.savedPlan)
        return (AppEnvironment.fake(fakes: fakes), fakes)
    }

    func test_emptyList() async {
        let (env, _) = env(plans: [])
        let model = TripsFixtures.model(env)
        await model.load()
        await assertSnapshots(
            of: { TripsRootView(env: env, model: model) }, named: "empty", configs: Self.configs, layout: .screen)
    }

    func test_list() async {
        let (env, _) = env(plans: TripsFixtures.all)
        env.device.travellerTypes = ["BUDGET_BACKPACKER"]
        let model = TripsFixtures.model(env)
        await model.load()
        await assertSnapshots(
            of: { TripsRootView(env: env, model: model) }, named: "list", configs: Self.configs, layout: .screen)
    }

    func test_detail() async {
        let (env, _) = env(plans: TripsFixtures.all)
        let detail = PlanDetailModel(
            env: env, planID: 2, files: MemoryFileStore(), now: { TripsFixtures.now }, calendar: TripsFixtures.calendar)
        await detail.load()
        await assertSnapshots(
            of: { NavigationStack { PlanDetailView(env: env, model: detail) } },
            named: "detail", configs: Self.configs, layout: .screen)
    }

    /// The trip is under way (2026-11-12 sits inside it) and the server has Sharing 2.0: "Share status" shows (R15).
    /// iPad canvas = content height (~708 pt) + 16 pt, so the capture has no blank tail.
    private static let statusShareConfigs: [SnapshotConfig] = {
        var pad = [SnapshotConfig.padLight, .padDark]
        for index in pad.indices { pad[index].canvas = CGSize(width: 834, height: 724) }
        return [.phoneLight, .phoneDark] + pad
    }()

    func test_statusShareEntry() async {
        let fakes = FakeRepositories()
        fakes.plans.onGet.returns(TripsFixtures.activePlan)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["sharing": .number(1)]))
        let detail = PlanDetailModel(
            env: env, planID: 2, files: MemoryFileStore(), now: { TripsFixtures.now }, calendar: TripsFixtures.calendar)
        await detail.load()
        await assertSnapshots(
            of: { NavigationStack { PlanDetailView(env: env, model: detail) } },
            named: "statusShare", configs: Self.statusShareConfigs, layout: .screen)
    }

    func test_splitWithSelectedPlan() async {
        let (env, _) = env(plans: TripsFixtures.all)
        let model = TripsFixtures.model(env)
        await model.load()
        let detail = PlanDetailModel(
            env: env, planID: 2, files: MemoryFileStore(), now: { TripsFixtures.now }, calendar: TripsFixtures.calendar)
        await detail.load()
        await assertSnapshots(
            of: { TripsRootView(env: env, model: model, selectedID: 2, detailModel: { _ in detail }) },
            named: "split", configs: [.padLight, .padDark], layout: .screen)
    }
}
