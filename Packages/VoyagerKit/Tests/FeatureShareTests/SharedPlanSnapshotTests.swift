import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureShare

@MainActor
final class SharedPlanSnapshotTests: XCTestCase {
    private let configs: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 460)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 460)),
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 435)),
    ]

    func test_sharedPlan() async {
        await assertSnapshots(
            of: {
                let fakes = FakeRepositories()
                let env = AppEnvironment.fake(user: nil, fakes: fakes)
                let model = SharedPlanModel(env: env, token: "abc12345")
                model.show(
                    SharedPlan(
                        name: "Tokyo",
                        searchData: [
                            "origin": "London", "destination": "Tokyo", "num_travelers": 2,
                            "import_source": ["url": "https://blog.example/tokyo", "title": "48 hours in Tokyo"],
                        ],
                        selections: ["activities": [["name": "Tsukiji food tour", "price_usd": 85]]],
                        kind: "plan", ownerName: "Amy"))
                return SharedPlanView(model: model)
            }, named: "plan", configs: configs, layout: .screen)
    }
}

@MainActor
final class SharedViewerSnapshotTests: XCTestCase {
    private func phone(_ name: String, dark: Bool = false, height: CGFloat) -> SnapshotConfig {
        SnapshotConfig(name: name, device: .iPhoneSe(.portrait), dark: dark, canvas: CGSize(width: 320, height: height))
    }

    private func view(_ plan: SharedPlan?) -> SharedPlanView {
        let env = AppEnvironment.fake(user: nil, fakes: FakeRepositories())
        let model = SharedPlanModel(env: env, token: "abc12345")
        if let plan { model.show(plan) } else { model.showNotFound() }
        return SharedPlanView(model: model)
    }

    private let recap = SharedPlan(
        name: "Japan trip", kind: "recap", ownerName: "Amy",
        card: SharedCard(
            headline: "My trip to Japan: recap",
            stats: [.init(key: "places", count: 9), .init(key: "activities", count: 4)], destination: "Japan", period: "2026-05"))

    func test_sharedRecap() async {
        await assertSnapshots(
            of: { view(recap) }, named: "recap", configs: [phone("se-light", height: 560)], layout: .screen)
    }

    func test_sharedRecapDark() async {
        await assertSnapshots(
            of: { view(recap) }, named: "recapDark", configs: [phone("se-dark", dark: true, height: 560)], layout: .screen)
    }

    func test_sharedSavings() async {
        let savings = SharedPlan(
            name: "Price alerts", kind: "savings",
            card: SharedCard(
                headline: "Caught drops worth $412",
                stats: [.init(key: "drops_caught", count: 3), .init(key: "targets_hit", count: 1)]))
        await assertSnapshots(
            of: { view(savings) }, named: "savings", configs: [phone("se-light", height: 560)], layout: .screen)
    }

    func test_sharedUnknownKind() async {
        let quiz = SharedPlan(name: "Quiz", kind: "quiz", card: SharedCard(headline: "Flags quiz: 4/5"))
        await assertSnapshots(
            of: { view(quiz) }, named: "unknownKind", configs: [phone("se-light", height: 400)], layout: .screen)
    }

    func test_sharedRevoked404() async {
        await assertSnapshots(
            of: { view(nil) }, named: "revoked404", configs: [phone("se-light", height: 400)], layout: .screen)
    }
}
