import Foundation
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeaturePlan

enum PlanFixtures {
    static let searchData: JSONValue = [
        "origin": "NYC", "destination": "Tokyo", "departure_date": "2026-12-05", "return_date": "2026-12-12",
        "interests": ["food"], "num_travelers": 2, "budget_usd": 3000,
    ]

    static let itinerary: JSONValue = [
        "days": [
            [
                "day_number": 1, "date": "2026-12-05", "theme": "Old Tokyo", "city": "Tokyo",
                "slots": [
                    ["time_of_day": "morning", "activity": "Senso-ji temple", "location": "Asakusa", "estimated_cost_usd": 0],
                    ["time_of_day": "afternoon", "activity": "Tsukiji food walk", "location": "Tsukiji", "estimated_cost_usd": 65],
                ],
            ],
            [
                "day_number": 2, "date": "2026-12-06", "theme": "Modern Tokyo", "city": "Tokyo",
                "slots": [["time_of_day": "morning", "activity": "Teamlab Planets", "location": "Toyosu", "estimated_cost_usd": 40]],
            ],
        ],
        "total_estimated_cost_usd": 105,
    ]

    static let selections: JSONValue = [
        "flight": nil,
        "flights": [["airline": "JAL", "flight_number": "JL5", "origin": "JFK", "destination": "HND", "price_usd": 980, "leg_index": 0]],
        "hotel": ["name": "Park Hotel Tokyo", "price_per_night_usd": 210, "total_price_usd": 1470],
        "activities": [["name": "Tsukiji food walk", "price_usd": 65], ["name": "Teamlab Planets", "price_usd": 40]],
        "places_to_see": [["name": "Meiji Shrine"]],
        "walking_tours": [],
        "sim": ["provider": "Ubigi", "plan_name": "Japan 5GB", "price_usd": 18],
        "tips": [["title": "Get a Suica card"]],
        "getting_around": [["name": "Metro day pass"]],
        "events": [],
        "itinerary_notes": [:],
        "itinerary_edits": [:],
        "itinerary_slots": [],
        "itinerary_layout": nil,
        "packing_list": nil,
        "itinerary": itinerary,
    ]

    static let saved = SavedPlan(id: 7, name: "Tokyo food trip", searchData: searchData, selections: selections)

    @MainActor
    static func env(
        signedIn: Bool = true, filled: Bool = true, fakes: FakeRepositories = FakeRepositories()
    ) -> AppEnvironment {
        let env = AppEnvironment.fake(user: signedIn ? .sample : nil, fakes: fakes)
        if filled {
            env.plan.selections = selections
            env.plan.searchData = searchData
            env.plan.isDirty = false
        }
        return env
    }
}
