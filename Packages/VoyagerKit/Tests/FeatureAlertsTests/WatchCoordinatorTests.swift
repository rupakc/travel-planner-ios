import Foundation
import Networking
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@MainActor
struct WatchCoordinatorTests {
    private let fareSpec: JSONValue = [
        "origin": "BER", "destination": "LIS", "departure_date": "2026-12-01", "return_date": "2026-12-08",
        "num_travelers": 2,
    ]
    private let hotelSpec: JSONValue = ["name": "Lumen Hotel", "city": "Lisbon", "check_in": "2026-12-10", "check_out": "2026-12-14"]

    @Test func test_matchBeforeCreate() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(.object(["id": 7]))
        let env = AppEnvironment.fake(fakes: fakes)
        let result = await env.watches.handle(.fare(fareSpec))
        #expect(result == .alreadyWatching(.flight, 7))
        #expect(fakes.watches.onMatch.callCount == 1)
        #expect(fakes.watches.onCreateFare.callCount == 0)
    }

    @Test func test_noMatchCreatesFare() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreateFare.returns(FareWatch(id: 12, alreadyWatching: false))
        let env = AppEnvironment.fake(fakes: fakes)
        let result = await env.watches.handle(.fare(fareSpec))
        #expect(result == .created(.flight, 12))
        #expect(fakes.watches.onMatch.callCount == 1)
        let sent = fakes.watches.onCreateFare.lastCall
        #expect(sent?.origin == "BER" && sent?.destination == "LIS")
        #expect(sent?.departureDate == "2026-12-01" && sent?.returnDate == "2026-12-08")
        #expect(sent?.numTravelers == 2 && sent?.alertMode == "any_drop")
    }

    @Test func test_createFiresTheWatchesChangedHookOnce() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreateFare.returns(FareWatch(id: 12, alreadyWatching: false))
        let env = AppEnvironment.fake(fakes: fakes)
        var calls = 0
        env.onWatchesChanged = { calls += 1 }
        _ = await env.watches.handle(.fare(fareSpec))
        #expect(calls == 1)
    }

    @Test func test_failedOrExistingCreateDoesNotFireTheHook() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreateFare.fails(APIError.network)
        let env = AppEnvironment.fake(fakes: fakes)
        var calls = 0
        env.onWatchesChanged = { calls += 1 }
        _ = await env.watches.handle(.fare(fareSpec))
        fakes.watches.onCreatePrice.returns(PriceWatch(id: 5, kind: .hotel, alreadyWatching: true))
        _ = await env.watches.handle(.hotel(hotelSpec))
        #expect(calls == 0)
    }

    @Test func test_noMatchCreatesPriceWatchUnderItsKind() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreatePrice.returns(PriceWatch(id: 5, kind: .hotel))
        let env = AppEnvironment.fake(fakes: fakes)
        let result = await env.watches.handle(.hotel(hotelSpec))
        #expect(result == .created(.hotel, 5))
        #expect(fakes.watches.onMatch.lastCall?.kind == .hotel)
        #expect(fakes.watches.onCreatePrice.lastCall?.kind == .hotel)
        #expect(fakes.watches.onCreatePrice.lastCall?.spec == hotelSpec)
    }

    @Test func test_serverSaysAlreadyWatching() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreatePrice.returns(PriceWatch(id: 5, kind: .hotel, alreadyWatching: true))
        let env = AppEnvironment.fake(fakes: fakes)
        #expect(await env.watches.handle(.hotel(hotelSpec)) == .alreadyWatching(.hotel, 5))
    }

    @Test func test_failedMatchStillCreates() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.fails(APIError.network)
        fakes.watches.onCreatePrice.returns(PriceWatch(id: 6, kind: .activity))
        let env = AppEnvironment.fake(fakes: fakes)
        #expect(await env.watches.handle(.activity(["name": "Tour", "city": "Lisbon"])) == .created(.activity, 6))
    }

    @Test func test_noLivePriceCopy() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        let body: JSONValue = [
            "detail": "We couldn't find live prices for this hotel on Google Hotels.", "code": "no_live_price",
            "message": "We couldn't find live prices for this hotel on Google Hotels.",
        ]
        fakes.watches.onCreatePrice.fails(
            APIError.client(status: 422, detail: "We couldn't find live prices for this hotel on Google Hotels.", code: "no_live_price", body: body))
        let env = AppEnvironment.fake(fakes: fakes)
        #expect(
            await env.watches.handle(.hotel(hotelSpec))
                == .noLivePrice("We couldn't find live prices for this hotel on Google Hotels."))
    }

    @Test func test_noLivePriceWithoutMessageFallsBackToCatalogue() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreatePrice.fails(APIError.client(status: 422, detail: nil, code: "no_live_price", body: .null))
        let env = AppEnvironment.fake(fakes: fakes)
        guard case .noLivePrice(let copy) = await env.watches.handle(.hotel(hotelSpec)) else {
            Issue.record("expected noLivePrice")
            return
        }
        #expect(!copy.isEmpty)
    }

    @Test func test_otherErrorsAreFailures() async {
        let fakes = FakeRepositories()
        fakes.watches.onMatch.returns(nil)
        fakes.watches.onCreateFare.fails(APIError.client(status: 409, detail: "limit", code: "watch_limit", body: .null))
        let env = AppEnvironment.fake(fakes: fakes)
        guard case .failed(let error) = await env.watches.handle(.fare(fareSpec)) else {
            Issue.record("expected failed")
            return
        }
        #expect(error.userFacingDetail == "limit")
    }
}
