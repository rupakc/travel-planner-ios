import Foundation
import Networking
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

@MainActor
struct NotificationsModelTests {
    private func note(_ id: Int, read: Bool = false, data: JSONValue = .null) -> AppNotification {
        AppNotification(
            id: id, kind: "fare_drop", title: "Berlin → Lisbon dropped to $454", body: "For 1–8 Dec", data: data,
            createdAt: iso(fixedNow.addingTimeInterval(-3600)), readAt: read ? iso(fixedNow) : nil)
    }

    private func model(_ env: AppEnvironment) -> NotificationsModel {
        NotificationsModel(env: env, track: { _ in }, now: { fixedNow })
    }

    @Test func test_markAllRead() async {
        let (env, fakes) = makeEnv {
            $0.notifications.onPage.returns(NotificationsPage(items: [note(1), note(2), note(3, read: true)], total: 3, unread: 2))
            $0.notifications.onMarkRead.returns(0)
        }
        let model = model(env)
        await model.load()
        #expect(model.unread == 2)
        await model.markAllRead()
        #expect(fakes.notifications.onMarkRead.lastCall?.all == true)
        #expect(fakes.notifications.onMarkRead.lastCall?.ids == nil)
        #expect(model.unread == 0)
        #expect(model.items.allSatisfy { $0.readAt != nil })
    }

    @Test func test_markOneRead() async {
        let (env, fakes) = makeEnv {
            $0.notifications.onPage.returns(NotificationsPage(items: [note(1), note(2)], total: 2, unread: 2))
            $0.notifications.onMarkRead.returns(1)
        }
        let model = model(env)
        await model.load()
        await model.markRead(model.items[0])
        #expect(fakes.notifications.onMarkRead.lastCall?.ids == [1])
        #expect(model.items[0].readAt != nil && model.items[1].readAt == nil)
        #expect(model.unread == 1)
    }

    @Test func test_inboxLinkFocusesWatch() async {
        let data: JSONValue = ["watch_id": 7, "links": ["alerts": "/alerts?watch=7"]]
        let (env, fakes) = makeEnv {
            $0.notifications.onPage.returns(NotificationsPage(items: [note(1, data: data)], total: 1, unread: 1))
            $0.notifications.onMarkRead.returns(0)
        }
        let model = model(env)
        await model.load()
        await model.open(model.items[0])
        #expect(env.recordedRoutes == [.alerts(kind: nil, watchID: 7)])
        #expect(fakes.notifications.onMarkRead.lastCall?.ids == [1])
    }

    @Test func test_linkWithKind() {
        let data: JSONValue = ["links": ["alerts": "/alerts?kind=hotel&watch=4", "book": "https://x"]]
        #expect(NotificationsModel.target(of: note(1, data: data)) == AlertTarget(kind: .hotel, watchID: 4))
        #expect(NotificationsModel.target(of: note(2, data: ["watch_id": 3])) == AlertTarget(kind: nil, watchID: 3))
        #expect(NotificationsModel.target(of: note(3, data: .null)) == nil)
        #expect(NotificationsModel.target(of: note(4, data: ["links": ["alerts": "/alerts?watch=-1"]]))?.watchID == nil)
    }

    @Test func test_notificationWithoutTargetOnlyMarksRead() async {
        let (env, _) = makeEnv {
            $0.notifications.onPage.returns(NotificationsPage(items: [note(1)], total: 1, unread: 1))
            $0.notifications.onMarkRead.returns(0)
        }
        let model = model(env)
        await model.load()
        await model.open(model.items[0])
        #expect(env.recordedRoutes.isEmpty)
    }

    @Test func test_notifications404HidesInbox() async {
        let (env, _) = makeEnv { $0.notifications.onPage.fails(APIError.notFound(nil)) }
        let model = model(env)
        await model.load()
        #expect(model.phase == .unavailable)
    }

    @Test func test_pagesLoadMore() async {
        let first = (1...20).map { note($0) }
        let second = (21...25).map { note($0) }
        let (env, fakes) = makeEnv {
            $0.notifications.onPage.handler = { call in
                call.offset == 0
                    ? NotificationsPage(items: first, total: 25, unread: 25)
                    : NotificationsPage(items: second, total: 25, unread: 25)
            }
        }
        let model = model(env)
        await model.load()
        #expect(model.hasMore)
        await model.loadMore()
        #expect(model.items.count == 25)
        #expect(!model.hasMore)
        #expect(fakes.notifications.onPage.calls.map(\.offset) == [0, 20])
    }

    @Test func test_failedLoadShowsError() async {
        let (env, _) = makeEnv { $0.notifications.onPage.fails(APIError.network) }
        let model = model(env)
        await model.load()
        guard case .failed = model.phase else { Issue.record("expected failed"); return }
    }
}
