import AuthCore
import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureSettings

@MainActor
final class SettingsSnapshotTests: XCTestCase {
    private func canvas(_ name: String, _ device: SnapshotDevice, dark: Bool, language: AppLanguage = .en) -> SnapshotConfig {
        let isPad = device == .iPadPro11
        return SnapshotConfig(
            name: name, device: device.config, dark: dark, language: language,
            canvas: CGSize(width: isPad ? 834 : 320, height: isPad ? 3200 : 4300))
    }

    private func screen(admin: Bool = false) -> SettingsRootView {
        let env = AppEnvironment.fake(user: admin ? User.sampleAdmin : User.sample)
        let model = SettingsModel(env: env, consentChoice: { .granted }, timeZone: "America/New_York", track: { _ in }, setConsent: { _ in })
        return SettingsRootView(model: model)
    }

    func test_settingsEnglish() async {
        await assertSnapshots(
            of: { screen() }, named: "you",
            configs: [
                canvas("se-light", .iPhoneSE, dark: false), canvas("se-dark", .iPhoneSE, dark: true),
                canvas("ipad-light", .iPadPro11, dark: false),
            ], layout: .screen)
    }

    func test_settingsAdmin() async {
        await assertSnapshots(
            of: { screen(admin: true) }, named: "admin",
            configs: [canvas("se-light", .iPhoneSE, dark: false)], layout: .screen)
    }

    func test_settingsHindiChineseBengali() async {
        await assertSnapshots(
            of: { screen() }, named: "lang",
            configs: [
                canvas("hi", .iPhoneSE, dark: false, language: .hi), canvas("zh", .iPhoneSE, dark: false, language: .zh),
                canvas("bn", .iPhoneSE, dark: false, language: .bn),
            ], layout: .screen)
    }

    func test_feedbackSheet() async {
        await assertSnapshots(
            of: { FeedbackSheet(env: AppEnvironment.fake()) {} }, named: "feedback",
            configs: [SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 900))],
            layout: .screen)
    }
}
