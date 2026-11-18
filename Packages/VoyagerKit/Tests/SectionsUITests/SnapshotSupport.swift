// Local copy of TestSupport's `assertSnapshots(of:named:)` (Task 14). Task 14 deletes this file.
import DesignSystem
import L10n
import SnapshotTesting
import SwiftUI
import UIKit
import VoyagerModel
import XCTest

enum SnapshotSetup {
    /// Same strict values as TestSupport.SnapshotSetup.
    static let precision: Float = 0.99995
    static let perceptualPrecision: Float = 0.99
    /// `TEST_RUNNER_SNAPSHOT_RECORD=1` (CI `record_snapshots`) records missing and changed PNGs; otherwise a missing PNG fails.
    static var record: SnapshotTestingConfiguration.Record {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .failed : .missing
    }
}

struct SnapshotConfig {
    let name: String
    let device: ViewImageConfig
    let dark: Bool
    var language: AppLanguage = .en
    var size: UIContentSizeCategory = .large
    /// A taller canvas than the device screen, so AX5 content is shown whole.
    var canvas: CGSize?

    static let phoneLight = SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false)
    static let phoneDark = SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true)
    static let padLight = SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false)
    static let padDark = SnapshotConfig(name: "ipad-dark", device: .iPadPro11(.portrait), dark: true)
    static let germanAX5 = SnapshotConfig(
        name: "se-de-ax5", device: .iPhoneSe(.portrait), dark: false, language: .de, size: .accessibilityExtraExtraExtraLarge,
        canvas: CGSize(width: 320, height: 1500))

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SemanticColor.surface.ignoresSafeArea())
                .ignoresSafeArea(.container, edges: .bottom)
            let traits = UITraitCollection { mutable in
                mutable.userInterfaceStyle = config.dark ? .dark : .light
                mutable.preferredContentSizeCategory = config.size
            }
            let canvas = fittedCanvas(
                of: view(), config: config,
                key: "\(testName.replacingOccurrences(of: "()", with: "")).\(name)-\(config.name)")
            withSnapshotTesting(record: SnapshotSetup.record) {
                assertSnapshot(
                    of: UIHostingController(rootView: content),
                    as: .image(
                        on: config.device, precision: SnapshotSetup.precision,
                        perceptualPrecision: SnapshotSetup.perceptualPrecision, size: canvas, traits: traits),
                    named: "\(name)-\(config.name)", file: file, testName: testName, line: line)
            }
        }
    }
}

/// Fits the canvas to the measured natural height of the padded component (plus safe area and a small tail), so a PNG
/// has no blank tail; falls back to the configured canvas when the view cannot be measured.
@MainActor
private func fittedCanvas(of view: some View, config: SnapshotConfig, key: String) -> CGSize? {
    guard let width = config.canvas?.width ?? config.device.size?.width else { return config.canvas }
    let probeHeight: CGFloat = 20_000
    let scheme: ColorScheme = config.dark ? .dark : .light
    let host = UIHostingController(
        rootView: view.padding(16).dynamicTypeSize(DynamicTypeSize(config.size) ?? .large).environment(\.colorScheme, scheme))
    let fit = host.sizeThatFits(in: CGSize(width: width, height: probeHeight))
    guard fit.height > 1, fit.height < probeHeight - 1 else {
        // Views that fill whatever height they are offered: measured from a record run (content height + 16 pt tail).
        let overrides: [String: CGFloat] = [
            "test_itinerary.plain-ipad-light": 866, "test_itinerary.plain-ipad-dark": 866,
            "test_itineraryEditedGerman.edited-se-de-ax5": 4500,
        ]
        guard let height = overrides[key] else { return config.canvas }
        return CGSize(width: width, height: height)
    }
    let safe = config.device.safeArea
    return CGSize(width: width, height: ceil(fit.height + safe.top + 4))
}
