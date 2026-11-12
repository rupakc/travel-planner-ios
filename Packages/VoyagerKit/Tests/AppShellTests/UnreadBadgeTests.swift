import Testing
import TestSupport

@testable import AppShell

@MainActor
@Suite struct UnreadBadgeTests {
    @Test func test_refreshStoresCountAndKeepsItOnFailure() async {
        let fakes = FakeRepositories()
        fakes.notifications.onUnreadCount.returns(4)
        let badge = UnreadBadge()
        await badge.refresh(fakes.notifications)
        #expect(badge.count == 4)

        fakes.notifications.onUnreadCount.fails(FakeRepositoryError.notScripted("x"))
        await badge.refresh(fakes.notifications)
        #expect(badge.count == 4)
    }
}
