import Foundation
import Networking
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

@MainActor
struct AlertsModelTests {
    private func loaded(
        kind: WatchKind? = nil, watchID: Int? = nil
    ) async -> (AlertsModel, FakeRepositories, AppEnvironment) {
        let (env, fakes) = makeEnv {
            $0.watches.onFareWatches.returns([fare(1), fare(2, status: "paused")])
            $0.watches.onPriceWatches.returns([hotel(4), activity(9)])
        }
        let model = makeModel(env, kind: kind, watchID: watchID)
        await model.load()
        return (model, fakes, env)
    }

    @Test func test_filterCounts() async {
        let (model, _, _) = await loaded()
        #expect(model.count(.all) == 4)
        #expect(model.count(.flight) == 2)
        #expect(model.count(.hotel) == 1)
        #expect(model.count(.activity) == 1)
        #expect(model.count(.trip) == 0)
        model.filter = .flight
        #expect(model.filtered.map(\.watchID) == [1, 2])
        // Pluralised status line: English one / other.
        #expect(model.statusText(.flight).contains("2"))
        #expect(model.statusText(.hotel).contains("1"))
    }

    @Test func test_focusSelectsKindAndWatch() async {
        let (model, _, _) = await loaded(kind: .hotel, watchID: 4)
        #expect(model.focusedID == "hotel-4")
        #expect(model.filter == .hotel)
    }

    @Test func test_oneListFailingStillShowsTheOther() async {
        let (env, _) = makeEnv {
            $0.watches.onFareWatches.fails(APIError.network)
            $0.watches.onPriceWatches.returns([hotel(4)])
        }
        let model = makeModel(env)
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.rows.count == 1)
        #expect(model.partialNotes.count == 1)
    }

    @Test func test_bothListsFailing() async {
        let (env, _) = makeEnv {
            $0.watches.onFareWatches.fails(APIError.network)
            $0.watches.onPriceWatches.fails(APIError.network)
        }
        let model = makeModel(env)
        await model.load()
        guard case .failed = model.phase else { Issue.record("expected failed"); return }
    }

    @Test func test_pauseThenResume() async {
        let (model, fakes, _) = await loaded()
        let row = model.rows[0]
        fakes.watches.onPatch.returns(.fare(fare(1, status: "paused")))
        await model.togglePause(row)
        #expect(fakes.watches.onPatch.lastCall?.patch.status == "paused")
        #expect(model.rows[0].isPaused)
        fakes.watches.onPatch.returns(.fare(fare(1)))
        await model.togglePause(model.rows[0])
        #expect(fakes.watches.onPatch.lastCall?.patch.status == "active")
        #expect(!model.rows[0].isPaused)
    }

    @Test func test_saveSendsTargetAndFlexibleForFares() async {
        let (model, fakes, _) = await loaded()
        fakes.watches.onPatch.returns(.fare(fare(1, mode: "below_target", target: 400, flexible: 3)))
        await model.save(model.rows[0], WatchEdit(alertMode: "below_target", target: 400, flexible: true, emailEnabled: false))
        let patch = fakes.watches.onPatch.lastCall?.patch
        #expect(patch?.alertMode == "below_target")
        #expect(patch?.targetPrice == 400)
        #expect(patch?.flexibleDays == 3)
        #expect(model.rows[0].belowTarget && model.rows[0].flexible)
    }

    @Test func test_savePriceWatchSendsNoFlexibleDays() async {
        let (model, fakes, _) = await loaded()
        let hotelRow = model.rows.first { $0.kind == .hotel }!
        fakes.watches.onPatch.returns(.price(hotel(4)))
        await model.save(hotelRow, WatchEdit(alertMode: "any_drop", target: nil, flexible: true, emailEnabled: true))
        #expect(fakes.watches.onPatch.lastCall?.patch.flexibleDays == nil)
        #expect(fakes.watches.onPatch.lastCall?.patch.emailEnabled == true)
    }

    @Test func test_deleteRemovesRow() async {
        let (model, fakes, _) = await loaded()
        await model.delete(model.rows[0])
        #expect(fakes.watches.onDelete.lastCall?.id == 1)
        #expect(model.count(.all) == 3)
    }

    @Test func test_deleteFailureKeepsRow() async {
        let (model, fakes, _) = await loaded()
        fakes.watches.onDelete.fails(APIError.network)
        await model.delete(model.rows[0])
        #expect(model.count(.all) == 4)
        #expect(model.toast != nil)
    }

    @Test func test_checkNowUpdatesRowAndSaysWhatHappened() async {
        let (model, fakes, _) = await loaded()
        fakes.watches.onCheck.returns(.fare(fare(1, last: 430, checkStatus: "checked")))
        await model.check(model.rows[0])
        #expect(model.rows[0].price == 430)
        #expect(model.toast?.text.contains("430") == true)
        fakes.watches.onCheck.returns(.fare(fare(1, checkStatus: "postponed")))
        await model.check(model.rows[0])
        #expect(model.toast?.text.isEmpty == false)
    }

    @Test func test_rateLimitedCheckShowsServerText() async {
        let (model, fakes, _) = await loaded()
        fakes.watches.onCheck.fails(APIError.rateLimited(message: "Daily budget spent", retryAfter: 60))
        await model.check(model.rows[0])
        #expect(model.toast?.text == "Daily budget spent")
    }

    @Test func test_liveCheckIsHeldInMemoryOnly() async {
        let (model, fakes, _) = await loaded()
        let result = LiveCheckResult(
            kind: .flight, watchID: 1, summary: "Around 440 on two sites",
            quotes: [LiveQuote(label: "Kayak", amount: 440, currency: "USD", sourceIndex: 0)],
            sources: [LiveSource(title: "Kayak", uri: "https://kayak.com/x")])
        fakes.watches.onLiveCheck.returns(result)
        await model.startLiveCheck(model.rows[0])
        #expect(fakes.watches.onLiveCheck.lastCall == LiveCheckRequest(kind: .flight, watchId: 1))
        #expect(model.liveCheck?.phase == .result(result))
        model.dismissLiveCheck()
        #expect(model.liveCheck == nil)
    }

    @Test func test_liveCheckFailureShowsServerDetail() async {
        let (model, fakes, _) = await loaded()
        fakes.watches.onLiveCheck.fails(APIError.server(status: 502, detail: "Live check failed"))
        await model.startLiveCheck(model.rows[0])
        #expect(model.liveCheck?.phase == .failed("Live check failed"))
    }

    @Test func test_pastWatchesGoLast() async {
        let (env, _) = makeEnv {
            $0.watches.onFareWatches.returns([fare(1, status: "expired"), fare(2)])
            $0.watches.onPriceWatches.returns([])
        }
        let model = makeModel(env)
        await model.load()
        #expect(model.activeRows.map(\.watchID) == [2])
        #expect(model.pastRows.map(\.watchID) == [1])
    }

    @Test func test_inboxHiddenOn404() async {
        let (env, _) = makeEnv { $0.notifications.onUnreadCount.fails(APIError.notFound(nil)) }
        let model = makeModel(env)
        await model.loadInbox()
        #expect(model.notifications404)
    }
}
