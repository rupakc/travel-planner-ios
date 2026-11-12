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
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 1400)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 1400)),
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 1200)),
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
