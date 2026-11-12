import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureSearch

@MainActor
final class SearchSnapshotTests: XCTestCase {
    /// Tall canvases: the form is a long scroll and the PNG should show all of it.
    private let configs = [
        SnapshotConfig(
            name: "se-de", device: .iPhoneSe(.portrait), dark: false, language: .de, canvas: CGSize(width: 320, height: 2300)),
        SnapshotConfig(
            name: "se-dark", device: .iPhoneSe(.portrait), dark: true, canvas: CGSize(width: 320, height: 2100)),
        SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 1700)),
        SnapshotConfig(name: "ipad-dark", device: .iPadPro11(.portrait), dark: true, canvas: CGSize(width: 834, height: 1700)),
    ]

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func filled(env: AppEnvironment) -> SearchFormModel {
        let model = SearchFormModel(env: env, now: { Self.fixedNow }, track: { _ in })
        model.pick(AirportSuggestion(iataCode: "FRA", city: "Frankfurt", country: "Germany"), into: model.origin)
        model.pick(AirportSuggestion(iataCode: "NRT", city: "Tokyo", country: "Japan"), into: model.destination)
        model.pick(NationalitySuggestion(nationality: "German", country: "Germany"))
        model.addStop()
        model.stops[0].place.set(external: "Seoul")
        model.setNights("3", forStop: model.stops[0].id)
        model.change(.children, by: 1)
        model.toggleInterest("food")
        model.toggleInterest("history")
        model.permits = ["Schengen"]
        model.budgetText = "4000"
        model.pace = "balanced"
        return model
    }

    func test_emptyForm() async {
        await assertSnapshots(
            of: {
                let env = AppEnvironment.fake()
                return SearchFormView(env: env, model: SearchFormModel(env: env, now: { Self.fixedNow }, track: { _ in }))
            }, named: "empty", configs: configs, layout: .screen)
    }

    func test_filledFormWithRecentSearches() async {
        let recents = [
            RecentSearch(
                id: 1,
                search: .object(["origin": "FRA", "destination": "Rome, Italy", "departure_date": "2027-03-01", "return_date": "2027-03-08"])),
            RecentSearch(
                id: 2, search: .object(["origin": "FRA", "destination": "Lisbon, Portugal", "departure_date": "2027-04-10"])),
        ]
        await assertSnapshots(
            of: {
                // The view loads the recent list itself, so the fake serves the same rows.
                let fakes = FakeRepositories()
                fakes.recent.onList.returns(recents)
                let env = AppEnvironment.fake(fakes: fakes)
                let model = filled(env: env)
                model.recents = recents
                return SearchFormView(env: env, model: model)
            }, named: "filled", configs: configs, layout: .screen)
    }
}
