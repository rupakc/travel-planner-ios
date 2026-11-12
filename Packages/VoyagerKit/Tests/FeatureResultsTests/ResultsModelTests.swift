import Foundation
import Networking
import os
import SectionsUI
import Telemetry
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureResults

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
    var announcements: [String] = []

    var firstSections: Int { events.filter { if case .searchFirstSection = $0 { true } else { false } }.count }
    var completes: Int { events.filter { if case .searchComplete = $0 { true } else { false } }.count }
    var abandons: Int { events.filter { if case .searchAbandon = $0 { true } else { false } }.count }
    var firstBytes: Int { events.filter { if case .perf(.ttfb, _, "/results") = $0 { true } else { false } }.count }
}

@MainActor
final class ResultsModelTests: XCTestCase {
    private let request = TravelSearchRequest(
        origin: "NYC", destination: "Tokyo", departureDate: "2026-04-01", returnDate: "2026-04-08")

    private func fixture() -> [SearchStreamEvent] {
        Fixtures.sse("search_full").map(SearchStreamEvent.init(json:))
    }

    private func make(
        _ configure: (FakeSearchRepository) -> Void
    ) -> (ResultsModel, AppEnvironment, FakeSearchRepository, Recorder) {
        let fakes = FakeRepositories()
        configure(fakes.search)
        let env = AppEnvironment.fake(fakes: fakes)
        let recorder = Recorder()
        let model = ResultsModel(
            env: env, request: request,
            track: { recorder.events.append($0) }, announce: { recorder.announcements.append($0) })
        return (model, env, fakes.search, recorder)
    }

    private func settle(_ model: ResultsModel, timeout: Double = 5) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !model.state.done, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Calls 1...n throw `.network` after `after` events; later calls replay everything.
    private func breaking(_ events: [SearchStreamEvent], after: Int, times: Int) -> @Sendable (TravelSearchRequest) -> AsyncThrowingStream<SearchStreamEvent, Error> {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        return { _ in
            let call = calls.withLock { value -> Int in
                value += 1
                return value
            }
            return AsyncThrowingStream { continuation in
                if call <= times {
                    for event in events.prefix(after) { continuation.yield(event) }
                    continuation.finish(throwing: APIError.network)
                } else {
                    for event in events { continuation.yield(event) }
                    continuation.finish()
                }
            }
        }
    }

    func test_fullStreamEndsDoneAndFeedsPlanStore() async {
        let events = fixture()
        let (model, env, search, recorder) = make { $0.onStream.replays(events) }
        model.start()
        await settle(model)
        XCTAssertTrue(model.state.done)
        XCTAssertFalse(model.interrupted)
        XCTAssertEqual(search.onStream.callCount, 1)
        XCTAssertNotNil(env.plan.latestResults["hotels"]["results"].array)
        XCTAssertNotNil(env.plan.latestResults["itinerary"]["days"].array)
        XCTAssertEqual(env.plan.searchData?["destination"].string, "Tokyo")
        XCTAssertEqual(recorder.completes, 1)
        XCTAssertFalse(recorder.announcements.isEmpty)
    }

    func test_interruptedStreamRetriesOnceAndKeepsSections() async {
        let events = fixture()
        let (model, _, search, recorder) = make { $0.onStream.handler = self.breaking(events, after: 5, times: 1) }
        model.start()
        await settle(model)
        XCTAssertEqual(search.onStream.callCount, 2)
        XCTAssertTrue(model.state.done)
        XCTAssertFalse(model.interrupted)
        XCTAssertEqual(model.state.sections.count, SectionID.allCases.count)
        XCTAssertNotNil(model.state.data(.tips), "static data is kept")
        XCTAssertNotNil(model.state.data(.visa))
        XCTAssertEqual(recorder.completes, 1)
        XCTAssertEqual(recorder.firstSections, 1)
        XCTAssertEqual(recorder.abandons, 0)
    }

    func test_secondInterruptionSetsInterrupted() async {
        let events = fixture()
        let (model, _, search, _) = make { $0.onStream.handler = self.breaking(events, after: 5, times: 2) }
        model.start()
        await settle(model)
        XCTAssertEqual(search.onStream.callCount, 2)
        XCTAssertTrue(model.interrupted)
        XCTAssertTrue(model.state.done)
        XCTAssertNotNil(model.state.data(.visa), "what arrived is kept")
        for id in SectionID.allCases { XCTAssertEqual(model.state.status(id), .done, id.rawValue) }
    }

    func test_streamEndingWithoutDoneIsRetried() async {
        let events = fixture().filter { if case .done = $0 { false } else { true } }
        let (model, _, search, _) = make { $0.onStream.replays(events) }
        model.start()
        await settle(model)
        XCTAssertEqual(search.onStream.callCount, 2)
        XCTAssertTrue(model.interrupted)
    }

    func test_nonNetworkFailureIsNotRetried() async {
        let (model, _, search, _) = make {
            $0.onStream.replays([], thenFails: APIError.rateLimited(message: "Slow down", retryAfter: 30))
        }
        model.start()
        await settle(model)
        XCTAssertEqual(search.onStream.callCount, 1)
        XCTAssertFalse(model.interrupted)
        XCTAssertEqual(model.failureMessage, "Slow down")
    }

    func test_modelSurvivesViewRebuild() async {
        let events = fixture()
        let (_, env, search, _) = make { $0.onStream.replays(events) }
        let host = ResultsHostingProbe(env: env, request: request)
        host.render(compact: true)
        let deadline = Date().addingTimeInterval(5)
        while search.onStream.callCount == 0, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        host.render(compact: false)
        host.render(compact: true)
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(search.onStream.callCount, 1, "a size-class change must not restart the stream")
    }

    func test_abandonOnlyBeforeDone() async {
        let (pending, _, _, pendingRecorder) = make { search in
            search.onStream.handler = { _ in AsyncThrowingStream { _ in } }
        }
        pending.start()
        try? await Task.sleep(for: .milliseconds(50))
        pending.cancel()
        pending.cancel()
        XCTAssertEqual(pendingRecorder.abandons, 1)

        let events = fixture()
        let (finished, _, _, finishedRecorder) = make { $0.onStream.replays(events) }
        finished.start()
        await settle(finished)
        finished.cancel()
        XCTAssertEqual(finishedRecorder.abandons, 0)

        let (neverStarted, _, _, idleRecorder) = make { _ in }
        neverStarted.cancel()
        XCTAssertEqual(idleRecorder.abandons, 0)
    }

    func test_firstSectionTimingSentOnce() async {
        let events = fixture()
        let (model, _, _, recorder) = make { $0.onStream.replays(events) }
        model.start()
        await settle(model)
        XCTAssertEqual(recorder.firstSections, 1)
        XCTAssertEqual(recorder.firstBytes, 1)
        XCTAssertEqual(recorder.completes, 1)
    }

    func test_toggleSelectsIntoPlanAndReportsOnce() {
        let (model, env, _, recorder) = make { _ in }
        let hotel: JSONValue = ["name": "Park Hyatt"]
        model.toggle(field: "activities", item: hotel)
        XCTAssertTrue(env.plan.contains(field: "activities", item: hotel))
        model.toggle(field: "activities", item: hotel)
        XCTAssertFalse(env.plan.contains(field: "activities", item: hotel))
        XCTAssertEqual(recorder.events.filter { if case .planSelect = $0 { true } else { false } }.count, 1)
    }

    func test_onlyHttpsLinksOpen() {
        let (model, _, _, recorder) = make { _ in }
        model.open(URL(string: "http://example.com/a")!, section: "hotels")
        XCTAssertNil(model.safariURL)
        model.open(URL(string: "https://example.com/a")!, section: "hotels")
        XCTAssertEqual(model.safariURL?.host(), "example.com")
        XCTAssertEqual(recorder.events.filter { if case .linkOut = $0 { true } else { false } }.count, 1)
    }

    func test_watchTextPerResult() {
        XCTAssertFalse(ResultsModel.watchText(.created(.flight, 1), kind: .flight).isEmpty)
        XCTAssertEqual(ResultsModel.watchText(.noLivePrice("No live price"), kind: .hotel), "No live price")
        XCTAssertNotEqual(
            ResultsModel.watchText(.alreadyWatching(.hotel, 2), kind: .hotel),
            ResultsModel.watchText(.failed(.network), kind: .hotel))
    }
}
