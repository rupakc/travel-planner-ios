import Foundation
import L10n
import Networking
import Telemetry
import Testing
import TestSupport
@testable import VoyagerEnv
import VoyagerModel

@MainActor
struct QuickWatchTests {
    private let hotelSpec: JSONValue = [
        "name": "Lumen Hotel", "city": "Lisbon", "check_in": "2026-12-10", "check_out": "2026-12-14", "plan_id": 3,
    ]
    private let fareSpec: JSONValue = [
        "origin": "BER", "destination": "LIS", "departure_date": "2026-12-01", "return_date": "2026-12-08", "num_travelers": 2,
    ]

    private func config(live: Bool = true, v2: Bool = true) -> ClientConfig {
        ClientConfig(features: ["alerts_api": .number(v2 ? 2 : 0), "price_alerts_v2": .bool(v2), "live_prices": .bool(live)])
    }

    private func pending(_ id: Int, existing: Bool = false) -> QuickWatchResult {
        QuickWatchResult(
            kind: .hotel, watch: .price(PriceWatch(id: id, kind: .hotel, pendingFirstCheck: !existing)), existing: existing)
    }

    private func coordinator(
        _ fakes: FakeRepositories, config: ClientConfig? = nil, events: Recorder = Recorder()
    ) -> (WatchCreateCoordinator, AppEnvironment) {
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config ?? self.config())
        return (WatchCreateCoordinator(env: env, track: { events.record($0) }), env)
    }

    @MainActor final class Recorder {
        var events: [TelemetryEvent] = []
        func record(_ event: TelemetryEvent) { events.append(event) }
        var quick: [String] {
            events.compactMap { event in
                if case .alertQuickWatch(let kind, let action, let surface) = event { return "\(kind)/\(action)/\(surface)" }
                return nil
            }
        }
    }

    // MARK: Button state

    @Test func test_buttonHiddenWithoutLivePrices() {
        let off = coordinator(FakeRepositories(), config: config(live: false)).0
        #expect(off.state(for: .hotel(hotelSpec)) == .off)
        #expect(QuickWatchState.off.isHidden)
        let on = coordinator(FakeRepositories()).0
        #expect(on.state(for: .hotel(hotelSpec)) == .idle)
        // An older backend without the flag keeps today's button.
        let older = coordinator(FakeRepositories(), config: ClientConfig(features: [:])).0
        #expect(older.state(for: .hotel(hotelSpec)) == .idle)
    }

    @Test func test_existingWatchShowsWatching() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.returns(pending(8, existing: true))
        let (watches, _) = coordinator(fakes)
        let result = await watches.handle(.hotel(hotelSpec))
        #expect(result == .alreadyWatching(.hotel, 8))
        #expect(watches.state(for: .hotel(hotelSpec)) == .existing(8))
        #expect(watches.state(for: .hotel(hotelSpec)).isWatching)
        #expect(watches.state(for: .activity(hotelSpec)) == .idle)
    }

    @Test func test_newOneTapWatchIsPendingAndOffersUndo() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.returns(pending(41))
        let events = Recorder()
        let (watches, env) = coordinator(fakes, events: events)
        var changed = 0
        env.onWatchesChanged = { changed += 1 }
        let result = await watches.handle(.hotel(hotelSpec), surface: .chat)
        #expect(result == .quickCreated(.hotel, 41))
        #expect(watches.state(for: .hotel(hotelSpec)) == .pending(41))
        #expect(watches.canUndo(kind: .hotel, id: 41))
        #expect(changed == 1)
        #expect(events.quick == ["hotel/add/chat"])
        let sent = fakes.alertsV2.onQuickWatch.lastCall
        #expect(sent?.title == "Lumen Hotel" && sent?.surface == .chat && sent?.planId == 3)
        #expect(sent?.subtitle == "Lisbon · 2026-12-10 – 2026-12-14")
        // The older create calls are not used on this path.
        #expect(fakes.watches.onMatch.callCount == 0 && fakes.watches.onCreatePrice.callCount == 0)
    }

    @Test func test_existingAnswerIsReportedAsExists() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.returns(pending(8, existing: true))
        let events = Recorder()
        let (watches, _) = coordinator(fakes, events: events)
        _ = await watches.handle(.hotel(hotelSpec))
        #expect(events.quick == ["hotel/exists/results"])
        #expect(!watches.canUndo(kind: .hotel, id: 8))
    }

    // MARK: Refusals

    @Test func test_limitAndOffMessages() async {
        let fakes = FakeRepositories()
        let events = Recorder()
        let (watches, _) = coordinator(fakes, events: events)
        fakes.alertsV2.onQuickWatch.fails(APIError.client(status: 409, detail: "limit", code: "watch_limit", body: .null))
        let limit = await watches.handle(.hotel(hotelSpec))
        #expect(limit == .refused(L10n.text(K.quickWatch.error.watch_limit)))
        #expect(watches.state(for: .hotel(hotelSpec)) == .limit)
        fakes.alertsV2.onQuickWatch.fails(APIError.server(status: 503, detail: "off", code: "live_prices_off"))
        let off = await watches.handle(.activity(["name": "Tour", "city": "Lisbon"]))
        #expect(off == .refused(L10n.text(K.quickWatch.error.live_prices_off)))
        #expect(watches.state(for: .hotel(hotelSpec)) == .off)
        #expect(events.quick == ["hotel/blocked/results", "activity/blocked/results"])
    }

    @Test func test_specInvalidAndGenericFailures() async {
        let fakes = FakeRepositories()
        let (watches, _) = coordinator(fakes)
        let blank = await watches.handle(.hotel(["city": "Lisbon"]))  // no name: no title
        #expect(blank == .refused(L10n.text(K.quickWatch.error.spec_invalid)))
        #expect(fakes.alertsV2.onQuickWatch.callCount == 0)
        fakes.alertsV2.onQuickWatch.fails(APIError.network)
        #expect(await watches.handle(.hotel(hotelSpec)) == .failed(.network))
    }

    @Test func test_limitClearsWhenAWatchIsRemoved() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.fails(APIError.client(status: 409, detail: nil, code: "watch_limit", body: .null))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config())
        let watches = env.watches  // the one `AppEnvironment.watchesChanged()` tells
        _ = await watches.handle(.hotel(hotelSpec))
        #expect(watches.state(for: .hotel(hotelSpec)) == .limit)
        await env.watchesChanged()
        #expect(watches.state(for: .hotel(hotelSpec)) == .idle)
    }

    // MARK: Undo

    @Test func test_undoRemovesWatch() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.returns(pending(41))
        let events = Recorder()
        let (watches, env) = coordinator(fakes, events: events)
        var changed = 0
        env.onWatchesChanged = { changed += 1 }
        _ = await watches.handle(.hotel(hotelSpec))
        #expect(await watches.undo(kind: .hotel, id: 41))
        #expect(fakes.watches.onDelete.callCount == 1)
        #expect(fakes.watches.onDelete.lastCall?.kind == .hotel && fakes.watches.onDelete.lastCall?.id == 41)
        #expect(watches.state(for: .hotel(hotelSpec)) == .idle)
        #expect(changed == 2)  // the create and the undo
        #expect(events.quick == ["hotel/add/results", "hotel/undo/results"])
        // A second Undo has nothing to remove.
        #expect(await watches.undo(kind: .hotel, id: 41) == false)
        #expect(fakes.watches.onDelete.callCount == 1)
    }

    @Test func test_failedUndoKeepsTheWatchAndAllowsRetry() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.returns(pending(41))
        let (watches, _) = coordinator(fakes)
        _ = await watches.handle(.hotel(hotelSpec))
        fakes.watches.onDelete.fails(APIError.network)
        #expect(await watches.undo(kind: .hotel, id: 41) == false)
        #expect(watches.state(for: .hotel(hotelSpec)) == .pending(41))
        #expect(watches.canUndo(kind: .hotel, id: 41))
    }

    // MARK: Older flow

    @Test func test_olderBackendKeepsTheMatchThenCreateFlow() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreateFare.returns(FareWatch(id: 12, alreadyWatching: false))
        let (watches, _) = coordinator(fakes, config: ClientConfig(features: [:]))
        let result = await watches.handle(.fare(fareSpec))
        #expect(result == .created(.flight, 12))
        #expect(fakes.alertsV2.onQuickWatch.callCount == 0)
        #expect(watches.state(for: .fare(fareSpec)) == .existing(12))
    }

    @Test func test_missingRouteFallsBackToTheOlderFlow() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onQuickWatch.fails(APIError.notFound(nil))
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreatePrice.returns(PriceWatch(id: 5, kind: .hotel))
        let (watches, _) = coordinator(fakes)
        let result = await watches.handle(.hotel(hotelSpec))
        #expect(result == .created(.hotel, 5))
    }

    // MARK: Title and subtitle

    @Test func test_draftTitles() {
        let flight = QuickWatchDraft(.fare(fareSpec))
        #expect(flight.title == "BER → LIS" && flight.subtitle == "2026-12-01 – 2026-12-08")
        let activity = QuickWatchDraft(.activity(["name": "Belém tour", "city": "Lisbon"]))
        #expect(activity.title == "Belém tour" && activity.subtitle == "Lisbon")
        let trip = QuickWatchDraft(.trip(["destination": "Lisbon", "departure_date": "2026-12-01"]))
        #expect(trip.title == "Lisbon" && trip.subtitle == "2026-12-01")
        #expect(QuickWatchDraft(.hotel([:])).title.isEmpty)
    }
}
