import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureImport

@MainActor
final class ImportSnapshotTests: XCTestCase {
    /// Canvases sized to the content (se, ipad heights in points) so there is no blank tail.
    private func configs(se: CGFloat, ipad: CGFloat) -> [SnapshotConfig] {
        [
            SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: se)),
            SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: se)),
            SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: ipad)),
        ]
    }

    func test_input() async {
        await assertSnapshots(
            of: { ImportView(model: ImportModel(env: AppEnvironment.fake(), track: { _ in })) },
            named: "input", configs: configs(se: 570, ipad: 500), layout: .screen)
    }

    func test_review() async {
        await assertSnapshots(
            of: {
                let model = ImportModel(env: AppEnvironment.fake(), now: Date(timeIntervalSince1970: 1_800_000_000), track: { _ in })
                model.origin = "London"
                model.nationality = "British"
                model.load(
                    LinkImportResult(
                        source: ImportSourceInfo(kind: "url", title: "Lisbon in 3 days"),
                        summary: "A relaxed long weekend.",
                        destinations: [ImportDestination(name: "Lisbon, Portugal", city: "Lisbon", nights: 3)],
                        places: [
                            ImportPlace(name: "Belem Tower", kind: "sight", destination: "Lisbon, Portugal"),
                            ImportPlace(name: "Time Out Market", kind: "food", destination: "Lisbon, Portugal", approximate: true),
                            ImportPlace(name: "Hotel Avenida", kind: "stay", destination: "Lisbon, Portugal"),
                        ],
                        unresolved: [ImportPlace(name: "Secret Cafe", kind: "food")]))
                return ImportView(model: model)
            }, named: "review", configs: configs(se: 1000, ipad: 990), layout: .screen)
    }
}
