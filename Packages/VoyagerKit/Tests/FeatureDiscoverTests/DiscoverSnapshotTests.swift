import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureDiscover

@MainActor
final class DiscoverSnapshotTests: XCTestCase {
    /// Tall canvases so the form and all five cards are in frame.
    private let configs: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 2400)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 2400)),
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 2000)),
    ]

    func test_fivePicks() async {
        await assertSnapshots(
            of: {
                let env = AppEnvironment.fake()
                let model = DiscoverModel(env: env, now: Date(timeIntervalSince1970: 1_800_000_000), track: { _ in })
                model.origin = "London"
                model.nationality = "British"
                model.toggle("food")
                model.show([
                    DiscoverSuggestion(
                        city: "Lisbon", country: "Portugal", estimatedCostUsdLow: 900, estimatedCostUsdHigh: 1400,
                        visaType: "visa_free", weatherEmoji: "☀️", matchReasons: ["Great food scene", "Walkable old town", "Third"]),
                    DiscoverSuggestion(city: "Tokyo", country: "Japan", visaType: "evisa", matchReasons: ["Food"]),
                    DiscoverSuggestion(city: "Lima", country: "Peru", visaType: "visa_on_arrival"),
                    DiscoverSuggestion(city: "Hanoi", country: "Vietnam", visaType: "required"),
                    DiscoverSuggestion(city: "Tbilisi", country: "Georgia"),
                ])
                return DiscoverView(model: model)
            }, named: "picks", configs: configs, layout: .screen)
    }
}
