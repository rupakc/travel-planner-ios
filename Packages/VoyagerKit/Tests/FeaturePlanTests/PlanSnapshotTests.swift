import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeaturePlan

@MainActor
final class PlanSnapshotTests: XCTestCase {
    private static let screenConfigs: [SnapshotConfig] =
        SnapshotConfig.matrix(devices: [.iPhoneSE, .iPhone15ProMax], schemes: [.light, .dark], languages: [.en])
        + [
            .padLight, .padDark,
            SnapshotConfig(name: "se-de-xxxl", device: SnapshotDevice.iPhoneSE.config, dark: false, language: .de, size: .extraExtraExtraLarge),
            SnapshotConfig(name: "se-ax3", device: SnapshotDevice.iPhoneSE.config, dark: false, size: .accessibilityExtraLarge),
        ]

    private func content(signedIn: Bool = true, filled: Bool = true) -> (MyPlanContent, AppEnvironment) {
        let env = PlanFixtures.env(signedIn: signedIn, filled: filled)
        env.plan.planName = "Tokyo food trip"
        return (MyPlanContent(model: MyPlanModel(env: env)), env)
    }

    func test_myPlan() async {
        let (view, env) = content()
        await assertSnapshots(
            of: { NavigationStack { view } }, named: "plan", configs: Self.screenConfigs, layout: .screen)
        _ = env
    }

    func test_myPlanSignedOutEmpty() async {
        let (view, env) = content(signedIn: false, filled: false)
        await assertSnapshots(
            of: { NavigationStack { view } }, named: "empty",
            configs: [.phoneLight, .phoneDark, .padLight], layout: .screen)
        _ = env
    }

    func test_costBreakdown() async {
        let parts = MyPlanModel.costParts(PlanFixtures.selections, searchData: PlanFixtures.searchData)
        let total = parts.reduce(0) { $0 + $1.amount }
        let budget = MyPlanModel.budgetNote(total: total, budget: 3000)
        await assertSnapshots(
            of: { CostBreakdownView(parts: parts, total: total, budget: budget, showsTransportNote: true) },
            named: "cost",
            configs: [
                .phoneLight, .phoneDark, .padLight,
                SnapshotConfig(name: "se-de-ax3", device: SnapshotDevice.iPhoneSE.config, dark: false, language: .de, size: .accessibilityExtraLarge),
            ], layout: .component)
    }

    func test_costOverBudget() async {
        let parts = MyPlanModel.costParts(PlanFixtures.selections, searchData: PlanFixtures.searchData)
        let total = parts.reduce(0) { $0 + $1.amount }
        await assertSnapshots(
            of: { CostBreakdownView(parts: parts, total: total, budget: MyPlanModel.budgetNote(total: total, budget: 1000), showsTransportNote: false) },
            named: "over", configs: [.phoneLight, .phoneDark], layout: .component)
    }

    func test_saveSheet() async {
        let (_, env) = content()
        let model = MyPlanModel(env: env)
        await assertSnapshots(
            of: { SaveSheet(model: model) }, named: "save", configs: [.phoneLight, .phoneDark, .padLight], layout: .screen)
    }
}
