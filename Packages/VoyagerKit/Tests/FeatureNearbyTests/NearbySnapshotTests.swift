import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureNearby

@MainActor
final class NearbySnapshotTests: XCTestCase {
    private let configs: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 1500)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 1500)),
    ]

    private static func model(_ phase: NearbyModel.Phase, _ result: NearbyResult? = nil) -> NearbyModel {
        let model = NearbyModel(env: AppEnvironment.fake(), location: FakeLocation(), track: { _ in })
        model.show(phase: phase, result: result)
        return model
    }

    func test_results() async {
        let response = NearbyResponse(
            place: NearbyPlace(name: "Lisbon"),
            sections: [
                NearbySection(
                    id: "see", title: "See",
                    items: [
                        NearbyItem(
                            name: "Castelo de Sao Jorge", summary: "Hilltop castle with city views",
                            mapsUri: "https://maps.google.com/?cid=1")
                    ]),
                NearbySection(
                    id: "eat", title: "Eat",
                    items: [NearbyItem(name: "Time Out Market", summary: "Food hall", mapsUri: "https://maps.google.com/?cid=2")]),
                NearbySection(id: "shop", title: "Shop", items: []),
            ],
            attribution: "Google Maps",
            sources: [NearbySource(title: "Google Maps", uri: "https://maps.google.com")])
        await assertSnapshots(
            of: { NearbyView(model: Self.model(.loaded, NearbyModel.result(from: response))) },
            named: "results", configs: configs, layout: .screen)
    }

    func test_denied() async {
        await assertSnapshots(
            of: { NearbyView(model: Self.model(.denied)) }, named: "denied", configs: configs, layout: .screen)
    }
}
