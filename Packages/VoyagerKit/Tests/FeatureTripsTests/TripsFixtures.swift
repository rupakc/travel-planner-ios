import Foundation
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureTrips

/// A fixed "today" (2026-11-12, UTC) so upcoming and past never depend on the clock.
enum TripsFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static let now = Date(timeIntervalSince1970: 1_794_484_800) // 2026-11-12 12:00 UTC

    static func plan(
        _ id: Int, _ name: String, destination: String = "Tokyo", from departure: String? = nil, to returning: String? = nil
    ) -> PlanSummary {
        var search: [String: JSONValue] = ["origin": "NYC", "destination": .string(destination)]
        if let departure { search["departure_date"] = .string(departure) }
        if let returning { search["return_date"] = .string(returning) }
        return PlanSummary(id: id, name: name, searchData: .object(search))
    }

    static let past = plan(1, "Old Paris", destination: "Paris", from: "2026-10-01", to: "2026-10-08")
    static let near = plan(2, "Tokyo food trip", from: "2026-12-05", to: "2026-12-12")
    static let far = plan(3, "Lisbon spring", destination: "Lisbon", from: "2027-03-01", to: "2027-03-08")
    static let undated = plan(4, "Someday Peru", destination: "Lima")

    static var all: [PlanSummary] { [past, far, undated, near] }

    static let savedPlan = SavedPlan(
        id: 2, name: "Tokyo food trip", searchData: near.searchData,
        selections: [
            "flights": [["name": "JFK to HND", "price_usd": 980]],
            "hotel": ["name": "Park Hotel Tokyo", "price_usd": 210],
            "activities": [["name": "Tsukiji food walk", "price_usd": 65], ["name": "Teamlab Planets"]],
            "tips": [["title": "Get a Suica card"]],
        ])

    @MainActor
    static func model(_ env: AppEnvironment, files: MemoryFileStore = MemoryFileStore()) -> TripsModel {
        TripsModel(env: env, files: files, now: { now }, calendar: calendar)
    }
}
