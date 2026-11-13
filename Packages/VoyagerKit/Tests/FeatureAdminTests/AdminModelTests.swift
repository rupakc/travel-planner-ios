import AuthCore
import Foundation
import Networking
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAdmin

@MainActor
private func make(user: User? = .sampleAdmin) -> (AdminRootModel, FakeRepositories) {
    let fakes = FakeRepositories()
    let env = AppEnvironment.fake(user: user, fakes: fakes)
    return (AdminRootModel(env: env), fakes)
}

private let rows = [
    AdminUser(id: 1, username: "root", isAdmin: true, isActive: true),
    AdminUser(id: 2, username: "amy", isAdmin: false, isActive: true),
    AdminUser(id: 3, username: "bob", isAdmin: false, isActive: false),
]

@MainActor
struct AdminModelTests {
    @Test func test_cannotDeactivateSelf() async {
        let (root, fakes) = make()
        fakes.admin.onUsers.returns(rows)
        await root.users.load()
        let me = rows[0]
        #expect(root.users.isSelf(me))
        #expect(!root.users.canDeactivate(me))
        await root.users.deactivate(me)
        #expect(fakes.admin.onDeactivate.callCount == 0)
        await root.users.deactivate(rows[2])  // already inactive
        #expect(fakes.admin.onDeactivate.callCount == 0)
        await root.users.deactivate(rows[1])
        #expect(fakes.admin.onDeactivate.calls == ["amy"])
        #expect(fakes.admin.onUsers.callCount == 2)  // reloaded after the change
    }

    @Test func test_reactivateOnlyInactive() async {
        let (root, fakes) = make()
        fakes.admin.onUsers.returns(rows)
        await root.users.load()
        await root.users.reactivate(rows[1])
        #expect(fakes.admin.onReactivate.callCount == 0)
        await root.users.reactivate(rows[2])
        #expect(fakes.admin.onReactivate.calls == ["bob"])
    }

    @Test func test_createNeedsEightCharacterPassword() async {
        let (root, fakes) = make()
        fakes.admin.onCreate.returns(AdminUser(id: 9, username: "new"))
        let short = await root.users.create(username: "new", password: "1234567", email: "", isAdmin: false)
        #expect(!short)
        #expect(fakes.admin.onCreate.callCount == 0)
        let ok = await root.users.create(username: " new ", password: "12345678", email: " ", isAdmin: true)
        #expect(ok)
        let sent = fakes.admin.onCreate.lastCall
        #expect(sent?.username == "new")
        #expect(sent?.email == nil)
        #expect(sent?.isAdmin == true)
    }

    @Test func test_createFailureKeepsSheetError() async {
        let (root, fakes) = make()
        fakes.admin.onCreate.fails(APIError.client(status: 409, detail: "taken", code: nil, body: .null))
        let ok = await root.users.create(username: "amy", password: "12345678", email: "", isAdmin: false)
        #expect(!ok)
        #expect(root.users.actionError?.userFacingDetail == "taken")
    }

    @Test func test_resetPasswordValidation() async {
        let (root, fakes) = make()
        #expect(await root.users.resetPassword(username: "amy", newPassword: "short", confirm: "short") == false)
        #expect(await root.users.resetPassword(username: "amy", newPassword: "12345678", confirm: "12345679") == false)
        #expect(fakes.admin.onResetPassword.callCount == 0)
        #expect(await root.users.resetPassword(username: "amy", newPassword: "12345678", confirm: "12345678"))
        #expect(fakes.admin.onResetPassword.lastCall?.username == "amy")
        #expect(root.users.resetDone == "amy")
    }

    @Test func test_analyticsHiddenOn404() async {
        let (root, fakes) = make()
        fakes.admin.onTelemetrySummary.fails(APIError.notFound(nil))
        root.selected = .analytics
        await root.start()
        #expect(root.tabs == [.users, .feedback])
        #expect(root.selected == .users)
        #expect(!root.analytics.isAvailable)
    }

    @Test func test_analyticsShownWhenAvailable() async {
        let (root, fakes) = make()
        fakes.admin.onTelemetrySummary.returns(TelemetrySummary(days: [TelemetryDay(day: "2026-11-01", users: 3, sessions: 4, events: 50)]))
        await root.start()
        #expect(root.tabs == [.users, .feedback, .analytics])
        #expect(fakes.admin.onTelemetrySummary.lastCall == 30)
    }

    @Test func test_analyticsOtherErrorsKeepTab() async {
        let (root, fakes) = make()
        fakes.admin.onTelemetrySummary.fails(APIError.server(status: 500, detail: nil))
        await root.start()
        #expect(root.tabs.contains(.analytics))
        #expect(root.analytics.phase == .failed)
    }

    @Test func test_nonAdminSeesNothing() async {
        let (root, fakes) = make(user: .sample)
        #expect(!root.isAdmin)
        #expect(root.tabs.isEmpty)
        await root.start()
        #expect(fakes.admin.onTelemetrySummary.callCount == 0)
        #expect(fakes.admin.onUsers.callCount == 0)
    }

    @Test func test_signedOutSeesNothing() {
        let (root, _) = make(user: nil)
        #expect(root.tabs.isEmpty)
    }

    @Test func test_feedbackFiltersReachTheRepo() async {
        let (root, fakes) = make()
        fakes.admin.onFeedback.returns([FeedbackEntry(username: "amy", page: "chat", rating: 99, category: "bug", message: "hi")])
        root.feedback.page = "chat"
        root.feedback.category = "bug"
        root.feedback.minRating = 4
        await root.feedback.load()
        let call = fakes.admin.onFeedback.lastCall
        #expect(call?.page == "chat" && call?.category == "bug" && call?.minRating == 4)
        #expect(root.feedback.entries.count == 1)
        #expect(root.feedback.filterKey == "chat|bug|4")
    }

    @Test func test_dailySeriesIsSortedAndRobust() async {
        let (root, fakes) = make()
        fakes.admin.onTelemetrySummary.returns(
            TelemetrySummary(days: [
                TelemetryDay(day: "2026-11-03", users: Int.max, sessions: 1, events: nil),
                TelemetryDay(day: "garbage", users: 5),
                TelemetryDay(day: "2026-11-01", users: Int.max, sessions: -4, events: 2),
            ]))
        await root.analytics.load()
        #expect(root.analytics.users.count == 2)
        #expect(root.analytics.users.first?.date ?? .distantFuture < root.analytics.users.last?.date ?? .distantPast)
        #expect(root.analytics.userDays7 == Int.max)  // saturates, never traps
        #expect(root.analytics.sessions.map(\.value) == [0, 1])  // negatives clamp to 0
    }
}
