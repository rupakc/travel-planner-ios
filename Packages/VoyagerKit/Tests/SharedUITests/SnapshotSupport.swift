// Local copy of TestSupport's `assertSnapshots(of:named:)` (Task 14). Task 14 deletes this file.
import DesignSystem
import L10n
import SnapshotTesting
import SwiftUI
import UIKit
import VoyagerModel
import XCTest

enum SnapshotSetup {
    /// `TEST_RUNNER_SNAPSHOT_RECORD=1` (CI `record_snapshots`) records; otherwise a missing PNG fails.
    static var record: SnapshotTestingConfiguration.Record {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .all : .missing
    }
}

struct SnapshotConfig {
    let name: String
    let device: ViewImageConfig
    let dark: Bool
    var language: AppLanguage = .en
    var size: UIContentSizeCategory = .large

    static let phoneLight = SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false)
    static let phoneDark = SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true)
    static let padLight = SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false)
    static let padDark = SnapshotConfig(name: "ipad-dark", device: .iPadPro11(.portrait), dark: true)
    static let germanAX5 = SnapshotConfig(
        name: "se-de-ax5", device: .iPhoneSe(.portrait), dark: false, language: .de, size: .accessibilityExtraExtraExtraLarge)

    static let standard: [SnapshotConfig] = [.phoneLight, .phoneDark, .padLight, .padDark, .germanAX5]
}

/// Renders `view` on iPhone SE and iPad, light and dark, plus German at AX5, one PNG each.
/// The view is built inside the language scope so `L10n` resolves in that language.
@MainActor
func assertSnapshots<V: View>(
    of view: @MainActor () -> V,
    named name: String,
    configs: [SnapshotConfig] = SnapshotConfig.standard,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    FontRegistry.registerOnce()
    for config in configs {
        LanguageController.withLanguage(config.language) {
            // A ScrollView proposes the content its natural height, so AX5 text never overlaps.
            let content = ScrollView { view().padding(16) }
                .background(SemanticColor.surface)
            let traits = UITraitCollection { mutable in
                mutable.userInterfaceStyle = config.dark ? .dark : .light
                mutable.preferredContentSizeCategory = config.size
            }
            withSnapshotTesting(record: SnapshotSetup.record) {
                assertSnapshot(
                    of: UIHostingController(rootView: content),
                    as: .image(on: config.device, precision: 0.99, perceptualPrecision: 0.98, traits: traits),
                    named: "\(name)-\(config.name)", file: file, testName: testName, line: line)
            }
        }
    }
}
