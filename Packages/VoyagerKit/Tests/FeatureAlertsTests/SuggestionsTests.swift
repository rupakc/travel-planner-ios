import Foundation
import L10n
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

@MainActor
struct SuggestionsTests {
    private let live = ClientConfig(features: ["alerts_api": .number(2), "price_alerts_v2": .bool(true), "live_prices": .bool(true)])

    private func suggestion(
        _ kind: WatchKind, _ title: String, reason: SuggestionReason = .selectedInPlan, already: Bool = false
    ) -> WatchSuggestion {
        WatchSuggestion(
            kind: kind, title: title, subtitle: "Lisbon", spec: .object(["name": .string(title)]), reason: reason,
            alreadyWatching: already)
    }

    @MainActor final class TrackLog {
        var events: [TelemetryEvent] = []
        var suggest: [String] {
            events.compactMap { if case .alertSuggest(let action, let count) = $0 { "\(action)/\(count)" } else { nil } }
        }
    }

    private func make(
        _ items: [WatchSuggestion], config: ClientConfig? = nil, livePrices: Bool = true
    ) -> (SuggestionsModel, FakeRepositories, TrackLog) {
        let fakes = FakeRepositories()
        fakes.alertsV2.onSuggestions.returns(WatchSuggestions(suggestions: items, livePrices: livePrices))
        fakes.alertsV2.onQuickWatch.handler = { request in
            QuickWatchResult(kind: request.kind, watch: .price(PriceWatch(id: 70, kind: request.kind, pendingFirstCheck: true)), existing: false)
        }
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: config ?? live)
        let log = TrackLog()
        return (SuggestionsModel(env: env, planID: 3, track: { log.events.append($0) }), fakes, log)
    }

    @Test func test_suggestionsHiddenWhenOff() async {
        for config in [
            ClientConfig(features: [:]),
            ClientConfig(features: ["alerts_api": .number(2), "price_alerts_v2": .bool(true), "live_prices": .bool(false)]),
        ] {
            let (model, fakes, log) = make([suggestion(.hotel, "Lumen")], config: config)
            #expect(!model.isAvailable)
            await model.load()
            #expect(model.phase == .hidden && model.rows.isEmpty)
            #expect(fakes.alertsV2.onSuggestions.callCount == 0)
            #expect(log.suggest.isEmpty)
        }
    }

    @Test func test_serverSayingNoLivePricesOrNothingToOfferHides() async {
        let (off, _, _) = make([suggestion(.hotel, "Lumen")], livePrices: false)
        await off.load()
        #expect(off.phase == .hidden)
        let (none, _, log) = make([])
        await none.load()
        #expect(none.phase == .hidden && log.suggest.isEmpty)
    }

    @Test func test_loadTicksNewOnesAndReportsShownOnce() async {
        let (model, _, log) = make([
            suggestion(.flight, "BER → LIS", reason: .tripTotal), suggestion(.hotel, "Lumen", already: true),
            suggestion(.activity, "Tour", reason: .unknown("new_reason")),
        ])
        await model.load()
        await model.load()
        #expect(model.phase == .loaded && model.rows.count == 3)
        #expect(model.rows.map(\.selected) == [true, false, true])
        #expect(model.rows[1].status == .already)
        #expect(model.selectedCount == 2)
        #expect(log.suggest == ["shown/3"])
        #expect(SuggestionsModel.reasonText(.unknown("new_reason")) == nil)
        #expect(SuggestionsModel.reasonText(.departureSoon) == L10n.text(K.watchSuggest.reason.departure_soon))
    }

    @Test func test_watchStartsTheTickedRowsAsSuggestSurface() async {
        let (model, fakes, log) = make([suggestion(.flight, "BER → LIS"), suggestion(.hotel, "Lumen"), suggestion(.activity, "Tour")])
        await model.load()
        model.toggle(model.rows[1].id)  // untick the hotel
        #expect(model.selectedCount == 2)
        await model.watchSelected()
        #expect(model.rows.map(\.status) == [.done, .idle, .done])
        #expect(fakes.alertsV2.onQuickWatch.calls.map(\.title) == ["BER → LIS", "Tour"])
        #expect(fakes.alertsV2.onQuickWatch.calls.allSatisfy { $0.surface == .suggest && $0.planId == 3 })
        #expect(log.suggest == ["shown/3", "accepted/2"])
        #expect(!model.isFinished)  // the unticked one is still open
    }

    @Test func test_limitStopsTheRest() async {
        let (model, fakes, _) = make([suggestion(.flight, "A"), suggestion(.hotel, "B"), suggestion(.activity, "C")])
        await model.load()
        fakes.alertsV2.onQuickWatch.fails(APIError.client(status: 409, detail: "limit", code: "watch_limit", body: .null))
        await model.watchSelected()
        #expect(fakes.alertsV2.onQuickWatch.callCount == 1)
        #expect(model.rows[0].status == .failed(L10n.text(K.watchSuggest.error.watch_limit)))
        #expect(model.rows[1].status == .idle && model.rows[2].status == .idle)
    }

    @Test func test_existingAnswerMarksAlready() async {
        let (model, fakes, _) = make([suggestion(.hotel, "Lumen")])
        await model.load()
        fakes.alertsV2.onQuickWatch.returns(
            QuickWatchResult(kind: .hotel, watch: .price(PriceWatch(id: 4, kind: .hotel)), existing: true))
        await model.watchSelected()
        #expect(model.rows[0].status == .already)
        #expect(model.isFinished)
    }

    @Test func test_dismissReportsOnceAndNotAfterAccepting() async {
        let (model, _, log) = make([suggestion(.hotel, "Lumen")])
        await model.load()
        model.dismiss()
        model.dismiss()
        #expect(log.suggest == ["shown/1", "dismissed/1"])
        let (accepting, _, log2) = make([suggestion(.hotel, "Lumen")])
        await accepting.load()
        await accepting.watchSelected()
        accepting.dismiss()
        #expect(log2.suggest == ["shown/1", "accepted/1"])
    }

    @Test func test_tripNotFoundIsAGenericError() async {
        let fakes = FakeRepositories()
        fakes.alertsV2.onSuggestions.fails(APIError.notFound("trip_not_found"))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: live)
        let model = SuggestionsModel(env: env, planID: 99, track: { _ in })
        await model.load()
        #expect(model.phase == .failed(L10n.text(K.watchSuggest.error.generic)))
    }
}
