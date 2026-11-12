import Foundation
import Networking
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureCompare

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
}

private func summary(_ name: String, total: Double, ease: Int = 70) -> CompareSummary {
    CompareSummary(
        destination: name, label: name, ease: CompareEase(total: ease),
        estimate: CompareEstimate(totalUsd: total))
}

@MainActor
private func makeModel(
    fakes: FakeRepositories, destinations: [String] = ["Lisbon", "Rome", "Athens"]
) -> (CompareModel, AppEnvironment, Recorder) {
    let env = AppEnvironment.fake(fakes: fakes)
    let recorder = Recorder()
    let model = CompareModel(
        env: env, now: Date(timeIntervalSince1970: 1_800_000_000), track: { recorder.events.append($0) })
    model.origin = "London"
    model.nationality = "British"
    model.destinations = destinations
    return (model, env, recorder)
}

@MainActor
struct CompareModelTests {
    @Test func test_columnsLoadIndependently() async {
        let fakes = FakeRepositories()
        fakes.compare.onSummary.handler = { request in
            switch request.destination {
            case "Rome": throw APIError.server(status: 503, detail: nil)
            case "Athens": throw APIError.rateLimited(message: "Too many requests, wait 60 s.", retryAfter: 60)
            default: return summary(request.destination ?? "", total: 900)
            }
        }
        let (model, _, _) = makeModel(fakes: fakes)
        await model.compare()

        #expect(model.columns.count == 3)
        #expect(model.columns[0].summary?.destination == "Lisbon")
        #expect(model.columns[1].isFailed)
        #expect(model.columns[2].status == .failed("Too many requests, wait 60 s."))
        #expect(fakes.compare.onSummary.callCount == 3)
        // Every request carries the shared fields; only the destination varies.
        let sent = fakes.compare.onSummary.calls
        #expect(Set(sent.compactMap(\.destination)) == ["Lisbon", "Rome", "Athens"])
        #expect(sent.allSatisfy { $0.origin == "London" && $0.nationality == "British" && $0.numTravelers == 1 })
    }

    @Test func test_retryOnlyFailedColumn() async {
        let fakes = FakeRepositories()
        fakes.compare.onSummary.handler = { request in
            if request.destination == "Rome" { throw APIError.server(status: 503, detail: nil) }
            return summary(request.destination ?? "", total: 800)
        }
        let (model, _, _) = makeModel(fakes: fakes, destinations: ["Lisbon", "Rome"])
        await model.compare()
        #expect(model.columns[1].isFailed)
        #expect(fakes.compare.onSummary.callCount == 2)

        fakes.compare.onSummary.handler = { request in summary(request.destination ?? "", total: 1200) }
        await model.retry(0)  // a finished column is never retried
        #expect(fakes.compare.onSummary.callCount == 2)
        await model.retry(1)

        #expect(fakes.compare.onSummary.callCount == 3)
        #expect(fakes.compare.onSummary.lastCall?.destination == "Rome")
        #expect(model.columns[1].summary?.estimate?.totalUsd == 1200)
        #expect(model.columns[0].summary?.estimate?.totalUsd == 800)
    }

    @Test func test_bestByRowHighlighted() {
        let (model, _, _) = makeModel(fakes: FakeRepositories(), destinations: ["A", "B", "C"])
        let request = TravelSearchRequest()
        model.show([
            CompareColumn(destination: "A", request: request, status: .done(summary("A", total: 1500, ease: 60))),
            CompareColumn(destination: "B", request: request, status: .done(summary("B", total: 900, ease: 80))),
            CompareColumn(destination: "C", request: request, status: .failed("x")),
        ])
        #expect(model.best["estimate"] == [1])
        #expect(model.best["ease"] == [1])
    }

    @Test func test_planThisTracksAndOpensResults() async throws {
        let fakes = FakeRepositories()
        fakes.compare.onSummary.handler = { request in summary(request.destination ?? "", total: 500) }
        let (model, env, recorder) = makeModel(fakes: fakes, destinations: ["Lisbon", "Rome"])
        await model.compare()
        model.plan(1)

        guard case .results(let search) = try #require(env.recordedRoutes.last) else {
            Issue.record("expected a results route")
            return
        }
        #expect(search.destination == "Rome")
        #expect(search.origin == "London")
        let modes = recorder.events.compactMap { event -> ExploreModeName? in
            if case .searchSubmit(let mode, _, _, _) = event { return mode }
            return nil
        }
        #expect(modes == [.compare])
    }

    @Test func test_needTwoDistinctDestinations() async {
        let fakes = FakeRepositories()
        let (model, _, _) = makeModel(fakes: fakes, destinations: ["Lisbon", " lisbon "])
        await model.compare()
        #expect(model.needTwo)
        #expect(model.columns.isEmpty)
        #expect(fakes.compare.onSummary.callCount == 0)
    }

    @Test func test_destinationCountBounds() {
        let (model, _, _) = makeModel(fakes: FakeRepositories(), destinations: ["A", "B"])
        #expect(!model.canRemoveDestination)
        model.addDestination()
        model.addDestination()
        #expect(model.destinations.count == 3)
        model.removeDestination(at: 0)
        #expect(model.destinations == ["B", ""])
    }
}
