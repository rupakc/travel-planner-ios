import AuthCore
import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureAdmin

@MainActor
final class AdminSnapshotTests: XCTestCase {
    private func canvas(_ name: String, _ device: SnapshotDevice, dark: Bool, language: AppLanguage = .en, height: CGFloat = 900) -> SnapshotConfig {
        let isPad = device == .iPadPro11
        return SnapshotConfig(
            name: name, device: device.config, dark: dark, language: language,
            canvas: CGSize(width: isPad ? 834 : 320, height: isPad ? 800 : height))
    }

    private func fakes() -> FakeRepositories {
        let fakes = FakeRepositories()
        fakes.admin.onUsers.returns([
            AdminUser(id: 1, username: "root", email: "root@example.com", isAdmin: true, isActive: true, createdAt: "2026-01-02T10:00:00"),
            AdminUser(id: 2, username: "amy", email: "amy@example.com", isAdmin: false, isActive: true, createdAt: "2026-03-04T10:00:00"),
            AdminUser(id: 3, username: "bob", isAdmin: false, isActive: false, createdAt: "2026-05-06T10:00:00"),
        ])
        fakes.admin.onFeedback.returns([
            FeedbackEntry(username: "amy", page: "results", rating: 4, category: "praise", message: "Loved the itinerary.", createdAt: "2026-11-01T09:00:00"),
            FeedbackEntry(username: "bob", page: "chat", rating: 2, category: "bug", message: "Chat stalled once.", createdAt: "2026-11-02T09:00:00"),
        ])
        let days = (1...14).map { TelemetryDay(day: String(format: "2026-11-%02d", $0), users: 3 + $0 % 5, sessions: 5 + $0, events: 40 + $0 * 7) }
        fakes.admin.onTelemetrySummary.returns(
            TelemetrySummary(
                days: days, topEvents: [TelemetryTopEvent(event: "ui_tap", events: 812), TelemetryTopEvent(event: "screen_view", events: 540)],
                topScreens: [TelemetryTopScreen(route: "/results", views: 120), TelemetryTopScreen(route: "/trips", views: 88)],
                users7d: 11))
        return fakes
    }

    private func started() async -> AdminRootModel {
        let model = AdminRootModel(env: AppEnvironment.fake(user: .sampleAdmin, fakes: fakes()))
        await model.users.load()
        await model.feedback.load()
        await model.start()
        return model
    }

    func test_users() async {
        let model = await started()
        await assertSnapshots(
            of: { AdminRootView(model: model) }, named: "users",
            configs: [canvas("se-light", .iPhoneSE, dark: false), canvas("se-dark", .iPhoneSE, dark: true), canvas("ipad-light", .iPadPro11, dark: false)],
            layout: .screen)
    }

    func test_feedback() async {
        let model = await started()
        model.selected = .feedback
        await assertSnapshots(
            of: { AdminRootView(model: model) }, named: "feedback",
            configs: [canvas("se-light", .iPhoneSE, dark: false, height: 1100), canvas("ipad-dark", .iPadPro11, dark: true)], layout: .screen)
    }

    func test_analytics() async {
        let model = await started()
        model.selected = .analytics
        await assertSnapshots(
            of: { AdminRootView(model: model) }, named: "analytics",
            configs: [canvas("se-light", .iPhoneSE, dark: false, height: 1900), canvas("ipad-light", .iPadPro11, dark: false)], layout: .screen)
    }

    func test_createSheet() async {
        let model = await started()
        await assertSnapshots(
            of: { CreateUserSheet(model: model.users) {} }, named: "create",
            configs: [canvas("se-light", .iPhoneSE, dark: false, height: 700)], layout: .screen)
    }

    func test_nonAdminIsBlank() async {
        let model = AdminRootModel(env: AppEnvironment.fake(user: .sample, fakes: fakes()))
        await assertSnapshots(
            of: { AdminRootView(model: model) }, named: "nonadmin",
            configs: [canvas("se-light", .iPhoneSE, dark: false, height: 300)], layout: .screen)
    }
}
