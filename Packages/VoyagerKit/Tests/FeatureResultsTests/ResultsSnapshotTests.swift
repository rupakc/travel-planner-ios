import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureResults

@MainActor
final class ResultsSnapshotTests: XCTestCase {
    private let request = TravelSearchRequest(
        origin: "New York", destination: "Tokyo", departureDate: "2026-04-01", returnDate: "2026-04-08")

    private let phone: [SnapshotConfig] = [
        SnapshotConfig(name: "se-light", device: .iPhoneSe(.portrait), dark: false, canvas: CGSize(width: 320, height: 2400)),
        SnapshotConfig(name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 2400)),
    ]
    private let pad: [SnapshotConfig] = [
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false),
        SnapshotConfig(name: "ipad-dark", device: .iPadPro11(.portrait), dark: true),
    ]

    private var events: [SearchStreamEvent] { Fixtures.sse("search_full").map(SearchStreamEvent.init(json:)) }

    private func state(prefix: Int? = nil) -> ResultsState {
        let search = ResultsModel.searchData(for: request)
        let slice = prefix.map { Array(events.prefix($0)) } ?? events
        return slice.reduce(ResultsState(searchData: search), ResultsReducer.reduce)
    }

    private func screen(_ state: ResultsState) -> some View {
        let env = AppEnvironment.fake()
        let model = ResultsModel(env: env, request: request, track: { _ in }, announce: { _ in })
        model.freeze(state)
        return NavigationStack { ResultsView(env: env, model: model) }
    }

    func test_midStream() async {
        let mid = state(prefix: 14)
        XCTAssertFalse(mid.done)
        await assertSnapshots(of: { screen(mid) }, named: "mid", configs: phone + pad, layout: .screen)
    }

    func test_done() async {
        let done = state()
        XCTAssertTrue(done.done)
        await assertSnapshots(of: { screen(done) }, named: "done", configs: phone + pad, layout: .screen)
    }
}
