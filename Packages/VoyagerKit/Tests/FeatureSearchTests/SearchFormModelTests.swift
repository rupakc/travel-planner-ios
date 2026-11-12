import Foundation
import Telemetry
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureSearch

@MainActor
private final class Recorder {
    var events: [TelemetryEvent] = []
}

/// 2027-01-15 in every time zone's calendar day arithmetic.
private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func makeModel(
    fakes: FakeRepositories = FakeRepositories(), recorder: Recorder = Recorder(), debounce: Duration = .milliseconds(20),
    prefill: TravelSearchRequest? = nil
) -> (SearchFormModel, AppEnvironment) {
    let env = AppEnvironment.fake(fakes: fakes)
    let model = SearchFormModel(
        env: env, prefill: prefill, now: { fixedNow }, debounce: debounce, track: { recorder.events.append($0) })
    return (model, env)
}

@MainActor
private func fillRequired(_ model: SearchFormModel) {
    model.origin.set(external: "FRA")
    model.destination.set(external: "NRT")
    model.nationality.set(external: "German")
}

@MainActor
struct SearchFormModelTests {
    @Test func test_typeaheadDebouncesAndCancels() async {
        let fakes = FakeRepositories()
        fakes.reference.onAirports.returns([AirportSuggestion(iataCode: "CDG", city: "Paris", country: "France")])
        let (model, _) = makeModel(fakes: fakes)
        model.origin.edit("p")
        model.origin.edit("pa")
        model.origin.edit("par")
        model.origin.edit("pari")
        await model.origin.settled()
        #expect(fakes.reference.onAirports.calls.map(\.query) == ["pari"])
        #expect(model.origin.suggestions.first?.iataCode == "CDG")
        // A query under two characters asks nobody and clears the list.
        model.origin.edit("p")
        await model.origin.settled()
        #expect(fakes.reference.onAirports.callCount == 1)
        #expect(model.origin.suggestions.isEmpty)
    }

    @Test func test_pickingAnAirportSetsTheCodeAndClosesTheList() async {
        let fakes = FakeRepositories()
        fakes.reference.onAirports.returns([AirportSuggestion(iataCode: "CDG", city: "Paris", country: "France")])
        let (model, _) = makeModel(fakes: fakes)
        model.origin.edit("paris")
        await model.origin.settled()
        model.pick(AirportSuggestion(iataCode: "CDG", city: "Paris", country: "France"), into: model.origin)
        #expect(model.origin.value == "CDG")
        #expect(model.origin.text == "CDG — Paris, France")
        #expect(model.origin.suggestions.isEmpty)
    }

    @Test func test_returnBeforeDepartureInvalid() {
        let (model, env) = makeModel()
        fillRequired(model)
        #expect(model.issue == nil)
        model.returnDate = Calendar.current.date(byAdding: .day, value: -1, to: model.departure) ?? model.departure
        #expect(model.issue == .returnBeforeDeparture)
        #expect(!model.canSubmit)
        #expect(model.visibleIssue == .returnBeforeDeparture)
        #expect(model.submit() == nil)
        #expect(env.recordedRoutes.isEmpty)
        // No return date at all (one way) is fine.
        model.hasReturn = false
        #expect(model.issue == nil)
        #expect(model.nights == 0)
    }

    @Test func test_missingRequiredFieldsBlockSubmit() {
        let (model, env) = makeModel()
        #expect(model.issue == .missingRequired)
        #expect(model.visibleIssue == nil)
        #expect(model.submit() == nil)
        #expect(model.visibleIssue == .missingRequired)
        #expect(env.recordedRoutes.isEmpty)
    }

    @Test func test_submitWritesBackPreferences() async throws {
        let fakes = FakeRepositories()
        fakes.preferences.onGet.returns(Preferences(username: "rupak", nationality: "Indian", interests: ["art"], adults: 1))
        let recorder = Recorder()
        let (model, _) = makeModel(fakes: fakes, recorder: recorder)
        await model.load()
        #expect(model.nationality.value == "Indian")
        #expect(model.interests == ["art"])
        fillRequired(model)
        model.toggleInterest("food")
        model.change(.children, by: 1)
        model.budgetText = "6000"
        let work = try #require(model.submit())
        await work.value

        let put = try #require(fakes.preferences.onPut.lastCall)
        #expect(put.username == "rupak")
        #expect(put.nationality == "German")
        #expect(put.interests == ["art", "food"])
        #expect(put.children == 1)
        #expect(put.numTravelers == 2)
        #expect(put.budgetCategory == "high")
        #expect(fakes.preferences.onPut.callCount == 1)

        let recorded = try #require(fakes.recent.onRecord.lastCall)
        #expect(recorded["origin"].string == "FRA")
        #expect(recorded["destination"].string == "NRT")
        #expect(recorded["children"].int == 1)
        #expect(recorded["budget_usd"].double == 6000)
        let submitted = recorder.events.compactMap { event -> String? in
            if case .searchSubmit(let mode, let travelers, let nights, let multiCity) = event {
                return "\(mode.rawValue) \(travelers) \(nights) \(multiCity)"
            }
            return nil
        }
        #expect(submitted == ["search 2 7 false"])
    }

    @Test func test_submitSkipsWriteBackWhenNothingChanged() async throws {
        let fakes = FakeRepositories()
        fakes.preferences.onGet.returns(Preferences(nationality: "Indian", interests: ["art"]))
        let (model, _) = makeModel(fakes: fakes)
        await model.load()
        model.origin.set(external: "DEL")
        model.destination.set(external: "LHR")
        let work = try #require(model.submit())
        await work.value
        #expect(fakes.preferences.onPut.callCount == 0)
        #expect(fakes.recent.onRecord.callCount == 1)
    }

    @Test func test_submitSetsLocale() throws {
        let (model, env) = makeModel()
        env.language.language = .de
        fillRequired(model)
        model.submit()
        let route = try #require(env.recordedRoutes.first)
        guard case .results(let request) = route else {
            Issue.record("expected .results, got \(route)")
            return
        }
        #expect(request.locale == .de)
        #expect(request.origin == "FRA")
        #expect(request.nationality == "German")
        #expect(request.numTravelers == 1)
        #expect(request.departureDate != nil)
    }

    @Test func test_multiCityNightsLengthMatches() throws {
        let (model, _) = makeModel()
        fillRequired(model)
        model.addStop()
        model.addStop()
        model.addStop()
        model.addStop()
        #expect(model.stops.count == 3)
        model.stops[0].place.set(external: "Rome")
        model.setNights("3", forStop: model.stops[0].id)
        model.stops[1].place.set(external: "Paris")
        // The third stop has no city: left out.
        let request = model.makeRequest()
        #expect(request.destinations == ["Rome", "Paris", "NRT"])
        #expect(request.destinationNights == [3, nil, nil])
        #expect(request.destinations?.count == request.destinationNights?.count)
        model.removeStop(id: model.stops[0].id)
        let fewer = model.makeRequest()
        #expect(fewer.destinations == ["Paris", "NRT"])
        #expect(fewer.destinationNights?.count == 2)
    }

    @Test func test_noStopsMeansNoJourney() {
        let (model, _) = makeModel()
        fillRequired(model)
        let request = model.makeRequest()
        #expect(request.destinations == nil)
        #expect(request.destinationNights == nil)
    }

    @Test func test_recentFillsForm() {
        let (model, _) = makeModel()
        let recent = RecentSearch(
            id: 7,
            search: .object([
                "origin": "FRA", "destination": "Tokyo, Japan", "departure_date": "2020-03-01", "return_date": "2020-03-11",
                "stops": .array([.object(["city": "Seoul", "nights": 2])]), "nationality": "German",
                "interests": ["food", "art"], "budget_usd": 3000, "adults": 2, "children": 1, "serendipity": 0.8,
            ]))
        model.fill(from: recent)
        #expect(model.origin.value == "FRA")
        #expect(model.destination.value == "Tokyo, Japan")
        #expect(model.nationality.value == "German")
        #expect(model.stops.count == 1)
        #expect(model.stops.first?.place.value == "Seoul")
        #expect(model.stops.first?.nights == "2")
        #expect(model.interests == ["food", "art"])
        #expect(model.budgetText == "3000")
        #expect(model.adults == 2)
        #expect(model.children == 1)
        #expect(model.serendipity == 0.8)
        // The dates had passed: a week from "today", keeping the ten-night length.
        #expect(model.notice == RecentNotice(route: "FRA → Tokyo", datesShifted: true))
        #expect(model.departure >= model.today)
        #expect(model.nights == 10)
        #expect(model.hasReturn)
    }

    @Test func test_recentWithFutureDatesKeepsThem() {
        let (model, _) = makeModel()
        let recent = RecentSearch(
            id: 1,
            search: .object([
                "origin": "LHR", "destination": "JFK", "departure_date": "2030-05-01", "return_date": .null, "nationality": "British",
            ]))
        model.fill(from: recent)
        #expect(SearchFormModel.iso(model.departure) == "2030-05-01")
        #expect(!model.hasReturn)
        #expect(model.notice?.datesShifted == false)
    }

    @Test func test_recentSearchesAreTheLastEight() async {
        let fakes = FakeRepositories()
        fakes.recent.onList.returns((1...10).map { RecentSearch(id: $0, search: .object(["origin": "A\($0)"])) })
        let (model, _) = makeModel(fakes: fakes)
        await model.load()
        #expect(model.recents.count == 8)
        #expect(model.recents.first?.id == 1)
    }

    @Test func test_deletingARecentSearch() async {
        let fakes = FakeRepositories()
        fakes.recent.onList.returns([RecentSearch(id: 1), RecentSearch(id: 2)])
        let (model, _) = makeModel(fakes: fakes)
        await model.load()
        await model.deleteRecent(model.recents[0]).value
        #expect(model.recents.map(\.id) == [2])
        #expect(fakes.recent.onDelete.calls == [1])

        struct Refused: Error {}
        fakes.recent.onDelete.fails(Refused())
        await model.deleteRecent(model.recents[0]).value
        #expect(model.recents.map(\.id) == [2])
    }

    @Test func test_partyStaysBetweenOneAndTwenty() {
        let (model, _) = makeModel()
        #expect(!model.canChange(.adults, by: -1))
        model.change(.adults, by: -1)
        #expect(model.adults == 1)
        model.change(.children, by: 1)
        #expect(model.canChange(.adults, by: -1))
        for _ in 0..<30 { model.change(.seniors, by: 1) }
        #expect(model.totalTravellers == 20)
        #expect(model.makeRequest().numTravelers == 20)
    }

    @Test func test_preferencesPreFillButNotOverARecentSearch() async {
        let fakes = FakeRepositories()
        fakes.preferences.onGet.returns(
            Preferences(budgetCategory: "medium", nationality: "Indian", interests: ["art"], adults: 2, children: 1))
        let (model, _) = makeModel(fakes: fakes)
        await model.load()
        #expect(model.budgetText == "3000")
        #expect(model.adults == 2)
        #expect(model.children == 1)
        #expect(model.nationality.value == "Indian")

        let (second, _) = makeModel(fakes: fakes)
        second.fill(from: RecentSearch(id: 1, search: .object(["origin": "A", "destination": "B", "adults": 1, "nationality": "French"])))
        await second.load()
        #expect(second.adults == 1)
        #expect(second.nationality.value == "French")
        #expect(second.budgetText.isEmpty)
    }

    @Test func test_prefillSplitsTheJourneyIntoStops() {
        let request = TravelSearchRequest(
            origin: "FRA", destination: "Lisbon", departureDate: "2030-06-01", returnDate: "2030-06-10",
            nationality: "German", destinations: ["Madrid", "Lisbon"], destinationNights: [4, nil])
        let (model, _) = makeModel(prefill: request)
        #expect(model.destination.value == "Lisbon")
        #expect(model.stops.count == 1)
        #expect(model.stops.first?.place.value == "Madrid")
        #expect(model.stops.first?.nights == "4")
        #expect(model.nights == 9)
    }

    @Test func test_signedOutSubmitOnlyOpensResults() {
        let env = AppEnvironment.fake(user: nil)
        let model = SearchFormModel(env: env, now: { fixedNow }, track: { _ in })
        fillRequired(model)
        #expect(model.submit() == nil)
        #expect(env.recordedRoutes.count == 1)
    }
}
