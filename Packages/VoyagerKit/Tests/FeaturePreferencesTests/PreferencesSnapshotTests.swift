import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeaturePreferences

@MainActor
final class PreferencesSnapshotTests: XCTestCase {
    private func canvas(_ name: String, _ device: SnapshotDevice, dark: Bool, language: AppLanguage = .en) -> SnapshotConfig {
        let isPad = device == .iPadPro11
        return SnapshotConfig(
            name: name, device: device.config, dark: dark, language: language,
            canvas: CGSize(width: isPad ? 834 : 320, height: isPad ? 2600 : 3000))
    }

    private func screen() async -> PreferencesView {
        var fakes = FakeRepositories()
        fakes.preferences.onGet.returns(
            Preferences(
                budgetCategory: "medium", nationality: "Indian", currentResidence: "Munich, Germany",
                residencePermits: ["Schengen"], existingVisas: ["US", "Japan"], interests: ["food", "art"],
                numTravelers: 3, adults: 2, children: 1, seniors: 0, infants: 0, accessibilityNeeds: ["wheelchair"]))
        fakes.preferences.onTaste.returns(
            TasteProfile(
                signals: [
                    "interest": [TasteSignal(value: "food", count: 5), TasteSignal(value: "history", count: 2)],
                    "hotel_tier": [TasteSignal(value: "mid-range", count: 3)],
                ], totalSignals: 10))
        let env = AppEnvironment.fake(fakes: fakes)
        let model = PreferencesModel(env: env, track: { _ in })
        let taste = TasteModel(env: env, track: { _ in })
        await model.load()
        await taste.load()
        return PreferencesView(model: model, taste: taste, email: EmailModel(env: env))
    }

    func test_preferencesLoaded() async {
        let view = await screen()
        await assertSnapshots(
            of: { view }, named: "prefs",
            configs: [
                canvas("se-light", .iPhoneSE, dark: false), canvas("se-dark", .iPhoneSE, dark: true),
                canvas("ipad-light", .iPadPro11, dark: false),
            ], layout: .screen)
    }

    func test_preferencesBengali() async {
        let view = await screen()
        await assertSnapshots(
            of: { view }, named: "prefs-lang",
            configs: [canvas("bn", .iPhoneSE, dark: false, language: .bn)], layout: .screen)
    }
}
