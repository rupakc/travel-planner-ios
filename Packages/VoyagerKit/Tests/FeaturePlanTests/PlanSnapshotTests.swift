import DesignSystem
import L10n
import SnapshotTesting
import SwiftUI
import TestSupport
import UIKit
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeaturePlan

private final class HeightBox: @unchecked Sendable { var value: CGFloat = 0 }

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

@MainActor
final class PlanSnapshotTests: XCTestCase {
    private static let screenConfigs: [SnapshotConfig] =
        SnapshotConfig.matrix(devices: [.iPhoneSE, .iPhone15ProMax], schemes: [.light, .dark], languages: [.en])
        + [
            .padLight, .padDark,
            SnapshotConfig(name: "se-de-xxxl", device: SnapshotDevice.iPhoneSE.config, dark: false, language: .de, size: .extraExtraExtraLarge),
            SnapshotConfig(name: "se-ax3", device: SnapshotDevice.iPhoneSE.config, dark: false, size: .accessibilityExtraLarge),
            SnapshotConfig(
                name: "se-de-ax3", device: SnapshotDevice.iPhoneSE.config, dark: false, language: .de, size: .accessibilityExtraLarge),
        ]

    /// The same configs on a canvas of the device's real width and the content's own height (plus the safe areas), so
    /// the whole scroll content shows. Width is never stretched; only the height follows the content.
    private func fullHeight(_ configs: [SnapshotConfig], padding: CGFloat = 0, view: () -> some View) -> [SnapshotConfig] {
        configs.map { config in
            var fitted = config
            let width = config.device.size?.width ?? 320
            let insets = config.device.safeArea
            LanguageController.withLanguage(config.language) {
                // Laid out in a real, very tall window so lazy and adaptive containers resolve like on a device; the
                // content reports its own height through a preference.
                let box = HeightBox()
                let content = view().padding(padding).frame(width: width).fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
                    .onPreferenceChange(HeightKey.self) { box.value = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .environment(\.dynamicTypeSize, DynamicTypeSize(config.size) ?? .large)
                let host = UIHostingController(rootView: content)
                host.traitOverrides.userInterfaceStyle = config.dark ? .dark : .light
                host.traitOverrides.preferredContentSizeCategory = config.size
                host.traitOverrides.horizontalSizeClass = width >= 600 ? .regular : .compact
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 40000))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                host.view.layoutIfNeeded()
                XCTAssertGreaterThan(box.value, 100, "the content did not report a height")
                fitted.canvas = CGSize(width: width, height: ceil(box.value + insets.top + insets.bottom))
                window.isHidden = true
            }
            return fitted
        }
    }

    private func content(signedIn: Bool = true, filled: Bool = true) -> (MyPlanContent, AppEnvironment) {
        let env = PlanFixtures.env(signedIn: signedIn, filled: filled)
        env.plan.planName = "Tokyo food trip"
        return (MyPlanContent(model: MyPlanModel(env: env)), env)
    }

    func test_myPlan() async {
        let (view, env) = content()
        await FontRegistry.ready()
        let configs = fullHeight(Self.screenConfigs) { view.scrollContent }
        await assertSnapshots(of: { view }, named: "plan", configs: configs, layout: .screen)
        _ = env
    }

    func test_myPlanSignedOutEmpty() async {
        let (view, env) = content(signedIn: false, filled: false)
        await assertSnapshots(
            of: { view }, named: "empty", configs: [.phoneLight, .phoneDark, .padLight], layout: .screen)
        _ = env
    }

    func test_costBreakdown() async {
        let parts = MyPlanModel.costParts(PlanFixtures.selections, searchData: PlanFixtures.searchData)
        let total = parts.reduce(0) { $0 + $1.amount }
        await FontRegistry.ready()
        let configs = fullHeight(
            [
                .phoneLight, .phoneDark, .padLight,
                SnapshotConfig(
                    name: "se-de-ax3", device: SnapshotDevice.iPhoneSE.config, dark: false, language: .de, size: .accessibilityExtraLarge),
            ], padding: 16
        ) { CostBreakdownView(
                parts: parts, total: total, budget: MyPlanModel.budgetNote(total: total, budget: 3000), showsTransportNote: true) }
        await assertSnapshots(
            of: { CostBreakdownView(
                parts: parts, total: total, budget: MyPlanModel.budgetNote(total: total, budget: 3000), showsTransportNote: true) },
            named: "cost", configs: configs, layout: .component)
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
