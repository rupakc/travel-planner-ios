import Domain
import SwiftUI
import TestSupport
import Telemetry
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureResults

@MainActor
final class PlanToolsTests: XCTestCase {
    private let request = TravelSearchRequest(
        origin: "New York", destination: "Tokyo", departureDate: "2026-04-01", returnDate: "2026-04-08", budgetUsd: 3000)

    private var done: ResultsState {
        let events = Fixtures.sse("search_full").map(SearchStreamEvent.init(json:))
        return events.reduce(ResultsState(searchData: ResultsModel.searchData(for: request)), ResultsReducer.reduce)
    }

    private func assertUsed(_ events: [TelemetryEvent], _ feature: String, line: UInt = #line) {
        guard events.count == 1, case .featureUsed(let name, let page) = events[0] else {
            return XCTFail("events: \(events.count)", line: line)
        }
        XCTAssertEqual(name, feature, line: line)
        XCTAssertEqual(page, "results", line: line)
    }

    func test_addAllThenUndoRestores() {
        var events: [TelemetryEvent] = []
        let env = AppEnvironment.fake()
        let tools = PlanToolsModel(env: env, track: { events.append($0) })
        let state = done
        let before = env.plan.selections
        let pkg = tools.package(results: state.latestResults, searchData: state.searchData, fit: nil)
        XCTAssertNotNil(pkg)
        guard let pkg else { return }
        tools.applyPackage(pkg)
        XCTAssertNotEqual(env.plan.selections, before)
        XCTAssertTrue(BestValuePackage.isApplied(env.plan.selections, pkg))
        XCTAssertNotNil(tools.toast)
        XCTAssertNotNil(tools.undoSelections)
        tools.undoPackage()
        XCTAssertEqual(env.plan.selections, before)
        XCTAssertNil(tools.undoSelections)
        assertUsed(events, "best_value")
    }

    func test_cheaperHotelsUsesFilteredRoute() async {
        let fakes = FakeRepositories()
        fakes.agents.onFiltered.returns(["results": [["name": "Budget Inn", "price_per_night_usd": 80]]])
        let env = AppEnvironment.fake(fakes: fakes)
        var events: [TelemetryEvent] = []
        let tools = PlanToolsModel(env: env, track: { events.append($0) })
        tools.findCheaperHotels(maxNightly: 90, searchData: done.searchData)
        XCTAssertEqual(tools.cheaper, .loading)
        let deadline = Date().addingTimeInterval(5)
        while tools.cheaper == .loading, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(fakes.agents.onFiltered.callCount, 1)
        XCTAssertEqual(fakes.agents.onFiltered.lastCall?.section, .hotels)
        XCTAssertEqual(fakes.agents.onFiltered.lastCall?.filters, ["max_price_per_night_usd": 90])
        XCTAssertEqual(fakes.agents.onFiltered.lastCall?.request.destination, "Tokyo")
        guard case .loaded(let cap, let hotels)? = tools.cheaper else { return XCTFail("not loaded: \(String(describing: tools.cheaper))") }
        XCTAssertEqual(cap, 90)
        XCTAssertEqual(hotels.count, 1)
        assertUsed(events, "budget_planner_cheaper_hotels")
    }

    func test_budgetEditsAreClientSideAndReportOnceWhenSettled() async {
        let fakes = FakeRepositories()
        let env = AppEnvironment.fake(fakes: fakes)
        var events: [TelemetryEvent] = []
        let tools = PlanToolsModel(env: env, track: { events.append($0) }, debounce: .milliseconds(60))
        let state = done
        guard let first = tools.allocation(searchData: state.searchData, results: state.latestResults) else {
            return XCTFail("no allocation")
        }
        for value in [300.0, 400, 500] {
            tools.change("stay", to: value, searchData: state.searchData, results: state.latestResults)
        }
        XCTAssertTrue(events.isEmpty, "nothing is reported while the slider is moving")
        XCTAssertEqual(tools.budgetEdit?.stay, 500)
        XCTAssertEqual(tools.budgetEdit?.sum, first.sum)
        tools.setTotal(.infinity, searchData: state.searchData, results: state.latestResults)
        XCTAssertEqual(tools.budgetEdit?.stay, 500)
        try? await Task.sleep(for: .milliseconds(300))
        assertUsed(events, "budget_planner")
        tools.resetBudget()
        XCTAssertNil(tools.budgetEdit)
        XCTAssertEqual(fakes.agents.onFiltered.callCount, 0)
    }

    func test_remixDiff() {
        var events: [TelemetryEvent] = []
        let env = AppEnvironment.fake()
        let tools = PlanToolsModel(env: env, track: { events.append($0) })
        let state = done
        let preset = Remix.presets.first { $0.id == "week_later" }
        guard let preset else { return XCTFail("no preset") }
        XCTAssertTrue(tools.remix(preset, searchData: state.searchData, results: state.latestResults))
        guard case .results(let remixed)? = env.recordedRoutes.last else { return XCTFail("no results route") }
        XCTAssertEqual(remixed.departureDate, "2026-04-08")
        assertUsed(events, "remix")
        let baseline = RemixBaselines.baseline(for: ResultsModel.searchData(for: remixed))
        XCTAssertEqual(baseline?.presetID, "week_later")
        XCTAssertEqual(baseline?.before["min_flight_usd"].double, 1200)
        // The remixed run came back cheaper: the diff shows the drop.
        let after = Remix.snapshotMetrics(["flights": ["results": [["price_usd": 900]]]])
        let rows = Remix.diffMetrics(baseline?.before, after, translate: PlanTranslator.text)
        XCTAssertEqual(rows.first?["direction"].string, "down")
        XCTAssertEqual(rows.first?["improved"].bool, true)
        RemixBaselines.removeAll()
    }

    func test_parseTotal() {
        XCTAssertEqual(PlanToolsFormat.parseTotal(" 2500.4 "), 2500)
        XCTAssertNil(PlanToolsFormat.parseTotal(""))
        XCTAssertNil(PlanToolsFormat.parseTotal("0"))
        XCTAssertNil(PlanToolsFormat.parseTotal("-5"))
        XCTAssertNil(PlanToolsFormat.parseTotal("abc"))
        XCTAssertNil(PlanToolsFormat.parseTotal(nil))
    }

    func test_remixBaselineKeepsOnlyTheLatest() {
        RemixBaselines.removeAll()
        let one: JSONValue = ["a": 1], two: JSONValue = ["a": 2]
        RemixBaselines.set(RemixBaseline(presetID: "luxe", before: .null), for: one)
        RemixBaselines.set(RemixBaseline(presetID: "week_later", before: .null), for: two)
        XCTAssertNil(RemixBaselines.baseline(for: one))
        XCTAssertEqual(RemixBaselines.baseline(for: two)?.presetID, "week_later")
        RemixBaselines.clear(for: two)
        XCTAssertNil(RemixBaselines.baseline(for: two))
    }

    func test_remixNotApplicableDoesNothing() {
        let env = AppEnvironment.fake()
        let tools = PlanToolsModel(env: env, track: { _ in })
        let bare = ResultsModel.searchData(for: TravelSearchRequest(destination: "Tokyo"))
        let luxe = Remix.presets.first { $0.id == "half_budget" }
        guard let luxe else { return XCTFail("no preset") }
        XCTAssertFalse(tools.remix(luxe, searchData: bare, results: .object([:])))
        XCTAssertTrue(env.recordedRoutes.isEmpty)
    }

    func test_looseJSONNeverTraps() {
        let results: JSONValue = [
            "flights": ["results": [["price_usd": "NaN"], ["price_usd": 1e308], ["outbound": 5]]],
            "hotels": ["results": [["name": 3, "price_per_night_usd": "1e999", "review_score": [1]]]],
        ]
        let sd: JSONValue = ["budget_usd": 1e300, "departure_date": "x", "return_date": 7]
        let env = AppEnvironment.fake()
        let tools = PlanToolsModel(env: env, track: { _ in })
        let computed = tools.fit(searchData: sd, results: results)
        XCTAssertNotNil(computed)
        XCTAssertEqual(computed?.0.sum.isFinite, true)
        let pkg = tools.package(results: results, searchData: sd, fit: computed?.1)
        XCTAssertTrue(pkg == nil || pkg?["items"].array != nil)
        XCTAssertNil(PlanToolsFormat.parseTotal("nan"))
        XCTAssertNil(PlanToolsFormat.parseTotal("1e999"))
        XCTAssertEqual(PlanToolsFormat.usd(.nan), "—")
        XCTAssertEqual(PlanToolsFormat.usd(1e300).isEmpty, false)
    }
}

@MainActor
final class PlanToolsSnapshotTests: XCTestCase {
    private let request = TravelSearchRequest(
        origin: "New York", destination: "Tokyo", departureDate: "2026-04-01", returnDate: "2026-04-08", budgetUsd: 3000)

    private let configs: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 2000)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 2000)),
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false),
    ]

    func test_panel() async {
        let events = Fixtures.sse("search_full").map(SearchStreamEvent.init(json:))
        let state = events.reduce(ResultsState(searchData: ResultsModel.searchData(for: request)), ResultsReducer.reduce)
        await assertSnapshots(
            of: {
                let env = AppEnvironment.fake()
                return ScrollView {
                    PlanToolsPanel(env: env, state: state, ctx: .inert).padding(16)
                }
            }, named: "panel", configs: configs, layout: .screen)
    }
}
