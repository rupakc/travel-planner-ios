import DesignSystem
import L10n
import SnapshotTesting
import SwiftUI
import UIKit
import VoyagerModel

/// `SNAPSHOT_RECORD=1` (CI `record_snapshots`, passed to the runner as `TEST_RUNNER_SNAPSHOT_RECORD`) records
/// every snapshot; otherwise a missing PNG is recorded and fails the test, and a changed one fails.
public enum SnapshotSetup {
    public static var record: SnapshotTestingConfiguration.Record {
        ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1" ? .all : .missing
    }
}

/// The devices snapshots render on. iPhone 15 Pro Max and iPad Pro 13" (M4) use their real point sizes and
/// safe areas with the traits of the nearest device swift-snapshot-testing ships.
public enum SnapshotDevice: String, CaseIterable, Sendable {
    case iPhoneSE = "se"
    case iPhone15ProMax = "15promax"
    case iPadPro11 = "ipad11"
    case iPadPro13 = "ipad13"

    public var config: ViewImageConfig {
        switch self {
        case .iPhoneSE:
            return .iPhoneSe(.portrait)
        case .iPhone15ProMax:
            return ViewImageConfig(
                safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
                size: CGSize(width: 430, height: 932),
                traits: ViewImageConfig.iPhone13ProMax(.portrait).traits)
        case .iPadPro11:
            return .iPadPro11(.portrait)
        case .iPadPro13:
            return ViewImageConfig(
                safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0),
                size: CGSize(width: 1032, height: 1376),
                traits: ViewImageConfig.iPadPro12_9(.portrait).traits)
        }
    }
}

/// How the view is hosted: a whole screen as it is, or a component in a padded `ScrollView` on the surface
/// colour (so tall content, such as AX5 text, is shown whole).
public enum SnapshotLayout: Sendable {
    case screen
    case component
}

/// One rendered PNG: `<name>-<config.name>.png`.
public struct SnapshotConfig: Sendable {
    public var name: String
    public var device: ViewImageConfig
    public var dark: Bool
    public var language: AppLanguage
    public var size: UIContentSizeCategory
    /// A canvas other than the device screen (taller for AX5).
    public var canvas: CGSize?

    public init(
        name: String, device: ViewImageConfig, dark: Bool, language: AppLanguage = .en,
        size: UIContentSizeCategory = .large, canvas: CGSize? = nil
    ) {
        self.name = name
        self.device = device
        self.dark = dark
        self.language = language
        self.size = size
        self.canvas = canvas
    }

    public static let phoneLight = SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false)
    public static let phoneDark = SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true)
    public static let padLight = SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false)
    public static let padDark = SnapshotConfig(name: "ipad-dark", device: .iPadPro11(.portrait), dark: true)
    public static let germanAX5 = SnapshotConfig(
        name: "se-de-ax5", device: .iPhoneSe(.portrait), dark: false, language: .de,
        size: .accessibilityExtraExtraExtraLarge, canvas: CGSize(width: 320, height: 1500))

    /// iPhone SE and iPad (light, dark) plus German at AX5: the component set SharedUI records.
    public static let standard: [SnapshotConfig] = [.phoneLight, .phoneDark, .padLight, .padDark, .germanAX5]

    /// Every device × scheme × language × size, named `<device>-<light|dark>[-<lang>][-<size>]`.
    public static func matrix(
        devices: [SnapshotDevice], schemes: [ColorScheme], languages: [AppLanguage],
        sizes: [UIContentSizeCategory] = [.large]
    ) -> [SnapshotConfig] {
        var result: [SnapshotConfig] = []
        for device in devices {
            for scheme in schemes {
                for language in languages {
                    for size in sizes {
                        var name = "\(device.rawValue)-\(scheme == .dark ? "dark" : "light")"
                        if language != .en { name += "-\(language.rawValue)" }
                        if size != .large { name += "-\(sizeName(size))" }
                        result.append(SnapshotConfig(
                            name: name, device: device.config, dark: scheme == .dark, language: language, size: size))
                    }
                }
            }
        }
        return result
    }

    static func sizeName(_ size: UIContentSizeCategory) -> String {
        switch size {
        case .accessibilityExtraExtraExtraLarge: return "ax5"
        case .accessibilityExtraExtraLarge: return "ax4"
        case .accessibilityExtraLarge: return "ax3"
        case .accessibilityLarge: return "ax2"
        case .accessibilityMedium: return "ax1"
        case .extraExtraExtraLarge: return "xxxl"
        case .extraExtraLarge: return "xxl"
        case .extraLarge: return "xl"
        case .medium: return "m"
        case .small: return "s"
        case .extraSmall: return "xs"
        default: return "size"
        }
    }
}

/// Snapshots `view` on every device × colour scheme × language (default: iPhone SE, iPhone 15 Pro Max and
/// iPad Pro 13", light and dark, English). It waits for the bundled fonts first. The view is rendered inside the language
/// scope, so `L10n` calls made in `body` use that language; build the view in a closure (the other overload)
/// when its initializer reads strings too.
@MainActor
public func assertSnapshots(
    of view: some View,
    named name: String,
    devices: [SnapshotDevice] = [.iPhoneSE, .iPhone15ProMax, .iPadPro13],
    schemes: [ColorScheme] = [.light, .dark],
    languages: [AppLanguage] = [.en],
    sizes: [UIContentSizeCategory] = [.large],
    layout: SnapshotLayout = .screen,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) async {
    await assertSnapshots(
        of: { view }, named: name,
        configs: SnapshotConfig.matrix(devices: devices, schemes: schemes, languages: languages, sizes: sizes),
        layout: layout, file: file, testName: testName, line: line)
}

/// Like `assertSnapshots(of:named:devices:...)`, building the view inside each language scope.
@MainActor
public func assertSnapshots<V: View>(
    of view: @MainActor () -> V,
    named name: String,
    devices: [SnapshotDevice] = [.iPhoneSE, .iPhone15ProMax, .iPadPro13],
    schemes: [ColorScheme] = [.light, .dark],
    languages: [AppLanguage] = [.en],
    sizes: [UIContentSizeCategory] = [.large],
    layout: SnapshotLayout = .screen,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) async {
    await assertSnapshots(
        of: view, named: name,
        configs: SnapshotConfig.matrix(devices: devices, schemes: schemes, languages: languages, sizes: sizes),
        layout: layout, file: file, testName: testName, line: line)
}

/// One PNG per config, `<name>-<config.name>.png` in the test file's `__Snapshots__/`. `settle` waits that many
/// seconds before the capture, for hosts (a `TabView`) that lay their content out after the first frame.
@MainActor
public func assertSnapshots<V: View>(
    of view: @MainActor () -> V,
    named name: String,
    configs: [SnapshotConfig],
    layout: SnapshotLayout = .component,
    settle: TimeInterval = 0,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) async {
    // Bundled fonts must be registered before anything renders, or SwiftUI falls back to the system font.
    await FontRegistry.ready()
    for config in configs {
        LanguageController.withLanguage(config.language) {
            let content = hosted(view(), layout: layout)
            let traits = UITraitCollection { mutable in
                mutable.userInterfaceStyle = config.dark ? .dark : .light
                mutable.preferredContentSizeCategory = config.size
            }
            let image = Snapshotting<UIViewController, UIImage>.image(
                on: config.device, precision: 0.99, perceptualPrecision: 0.98, size: config.canvas, traits: traits)
            withSnapshotTesting(record: SnapshotSetup.record) {
                assertSnapshot(
                    of: UIHostingController(rootView: content),
                    as: settle > 0 ? .wait(for: settle, on: image) : image,
                    named: "\(name)-\(config.name)", file: file, testName: testName, line: line)
            }
        }
    }
}

@MainActor
private func hosted(_ view: some View, layout: SnapshotLayout) -> AnyView {
    switch layout {
    case .component:
        // A ScrollView proposes the content its natural height, so AX5 text never overlaps.
        return AnyView(ScrollView { view.padding(16) }.background(SemanticColor.surface))
    case .screen:
        return AnyView(view.background(SemanticColor.surface))
    }
}
