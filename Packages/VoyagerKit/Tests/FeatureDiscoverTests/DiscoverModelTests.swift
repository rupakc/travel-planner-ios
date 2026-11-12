import Foundation
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureDiscover

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
}

@MainActor
private func makeModel(fakes: FakeRepositories = FakeRepositories()) -> (DiscoverModel, AppEnvironment, Recorder) {
    let env = AppEnvironment.fake(fakes: fakes)
    let recorder = Recorder()
    let model = DiscoverModel(
        env: env, now: Date(timeIntervalSince1970: 1_800_000_000), track: { recorder.events.append($0) })
    model.origin = "London"
    model.nationality = "British"
    return (model, env, recorder)
}

private let tokyo = DiscoverSuggestion(city: "Tokyo", country: "Japan", matchReasons: ["Food"])

@MainActor
struct DiscoverModelTests {
    @Test func test_planThisOpensResults() async throws {
        let fakes = FakeRepositories()
        fakes.discover.onSuggestions.returns([tokyo])
        let (model, env, recorder) = makeModel(fakes: fakes)
        model.toggle("food")
        model.budget = "2500"
        await model.find()
        #expect(model.suggestions == [tokyo])

        model.planThis(tokyo)

        guard case .results(let search) = try #require(env.recordedRoutes.last) else {
            Issue.record("expected a results route")
            return
        }
        #expect(search.destination == "Tokyo, Japan")
        #expect(search.origin == "London")
        #expect(search.nationality == "British")
        #expect(search.interests == ["food"])
        #expect(search.budgetUsd == 2500)
        #expect(search.returnDate != nil && search.departureDate != nil)
        let submits = recorder.events.compactMap { event -> ExploreModeName? in
            if case .searchSubmit(let mode, _, _, _) = event { return mode }
            return nil
        }
        #expect(submits == [.discover])
    }

    @Test func test_aiLimitMessage() async {
        let fakes = FakeRepositories()
        let text = "AI limit reached for this month — try again on the 1st."
        fakes.discover.onSuggestions.fails(APIError.server(status: 503, detail: text))
        let (model, _, _) = makeModel(fakes: fakes)
        await model.find()
        #expect(model.phase == .failed(text))
    }

    @Test func test_rateLimitShowsBackendText() async {
        let fakes = FakeRepositories()
        fakes.discover.onSuggestions.fails(APIError.rateLimited(message: "Too many requests, wait 60 s.", retryAfter: 60))
        let (model, _, _) = makeModel(fakes: fakes)
        await model.find()
        #expect(model.phase == .failed("Too many requests, wait 60 s."))
    }

    @Test func test_requiresOriginAndNationality() async {
        let fakes = FakeRepositories()
        let (model, _, _) = makeModel(fakes: fakes)
        model.origin = "  "
        #expect(!model.canSubmit)
        await model.find()
        #expect(fakes.discover.onSuggestions.callCount == 0)
    }

    @Test func test_requestCarriesFormValues() async {
        let fakes = FakeRepositories()
        let (model, _, _) = makeModel(fakes: fakes)
        model.toggle("art")
        model.toggle("food")
        model.adults = 2
        await model.find()
        let sent = fakes.discover.onSuggestions.lastCall
        #expect(sent?.origin == "London")
        #expect(sent?.interests == ["food", "art"])
        #expect(sent?.adults == 2)
        #expect(sent?.departureDate == DiscoverModel.apiDate(model.departure))
    }
}
