import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureSettings

@MainActor
final class NotificationSettingsSnapshotTests: XCTestCase {
    private func canvas(
        _ name: String, _ device: SnapshotDevice = .iPhoneSE, dark: Bool = false, language: AppLanguage = .en, height: CGFloat = 1900,
        ax5: Bool = false
    ) -> SnapshotConfig {
        let isPad = device == .iPadPro11
        return SnapshotConfig(
            name: name, device: device.config, dark: dark, language: language,
            size: ax5 ? .accessibilityExtraExtraExtraLarge : .large,
            canvas: CGSize(width: isPad ? 834 : 320, height: isPad ? 1500 : height))
    }

    /// A loaded screen over fakes: the server's answer is `settings`, the iOS permission is `permission`.
    private func screen(
        _ settings: NotificationSettings, permission: NotificationPermissionState = .allowed, showsGame: Bool = true
    ) async -> NotificationSettingsView {
        let fakes = FakeRepositories()
        fakes.notificationSettings.onGet.returns(settings)
        let env = AppEnvironment.fake(
            fakes: fakes, clientConfig: ClientConfig(features: ["notifications_api": .number(1), "game": .bool(showsGame)]))
        let model = NotificationSettingsModel(
            env: env, permission: FakeNotificationPermission(permission),
            gameVisibility: { showsGame ? StaticGameVisibility.visible : .hidden }, track: { _ in })
        await model.load()
        return NotificationSettingsView(model: model)
    }

    private let live = NotificationSettings(
        categories: [.weather: false, .nearby: false], quietHours: QuietHoursPref(enabled: true, start: "22:00", end: "07:00"),
        dailyCap: 3, timezone: "Asia/Kolkata", quietHoursActive: false, pushFCM: false, pushAPNS: true, devices: 2)

    func test_notifSettingsLight() async {
        let view = await screen(live)
        await assertSnapshots(
            of: { view }, named: "NotifSettingsLight", configs: [canvas("se-light"), canvas("se-dark", dark: true)], layout: .screen)
    }

    func test_notifSettingsPermissionDenied() async {
        let view = await screen(live, permission: .denied)
        await assertSnapshots(
            of: { view }, named: "NotifSettingsPermissionDenied", configs: [canvas("se-light", height: 2300)], layout: .screen)
    }

    func test_notifSettingsPushUnavailable() async {
        var settings = live
        settings.pushAPNS = false
        settings.devices = 0
        settings.timezone = nil
        settings.quietHours.enabled = false
        let view = await screen(settings, permission: .notDetermined, showsGame: false)
        await assertSnapshots(
            of: { view }, named: "NotifSettingsPushUnavailable", configs: [canvas("se-light", height: 2300)], layout: .screen)
    }

    func test_notifSettingsLongLanguages() async {
        let view = await screen(live)
        await assertSnapshots(
            of: { view }, named: "NotifSettingsDE",
            configs: [canvas("de", language: .de, height: 2300), canvas("hi", language: .hi, height: 2500)], layout: .screen)
    }

    func test_notifSettingsAX5() async {
        let view = await screen(live)
        await assertSnapshots(
            of: { view }, named: "NotifSettingsAX5",
            configs: [canvas("de-ax5", language: .de, height: 9000, ax5: true)], layout: .screen)
    }

    func test_notifSettingsFormIPad() async {
        let view = await screen(live)
        await assertSnapshots(of: { view }, named: "NotifSettingsForm", configs: [canvas("ipad-light", .iPadPro11)], layout: .screen)
    }
}
