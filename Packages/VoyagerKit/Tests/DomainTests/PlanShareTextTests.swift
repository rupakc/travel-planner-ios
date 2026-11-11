import Testing
import VoyagerModel
@testable import Domain

/// The cases of Android's `PlanShareTextTest`, over the web's selections shape.
@Suite struct PlanShareTextTests {
    @Test func listsSelectionsWithTheirOwnPricesAndOnlyWebLinks() {
        let selections: JSONValue = [
            "flight": [
                "price_usd": 900, "source": "estimate", "booking_url": "https://flights.example/x",
                "outbound": ["airline": "ANA", "flight_number": "NH9", "origin": "JFK", "destination": "HND", "departure_date": "2027-04-01"],
            ],
            "hotel": ["name": "Park Hyatt", "price_per_night_usd": 450, "booking_url": "javascript:alert(1)"],
            "activities": [["name": "Sushi class"]],
        ]
        let text = PlanShareText.text(
            planName: "Tokyo Trip", searchData: ["origin": "JFK", "destination": "HND"], selections: selections, shareURL: nil, labels: .english)
        #expect(text.hasPrefix("Tokyo Trip\nJFK \u{2192} HND\n"))
        #expect(text.contains("ANA NH9 \u{00B7} JFK \u{2192} HND \u{00B7} 2027-04-01 \u{00B7} $900 (Estimate)"))
        #expect(text.contains("https://flights.example/x"))
        #expect(text.contains("Park Hyatt, $450 / night"))
        #expect(!text.contains("javascript"))
        // No price invented for an activity without one.
        #expect(text.hasSuffix("  \u{2022} Sushi class"))
    }

    @Test func addsTheItineraryWithEditsAndNotes() {
        let selections: JSONValue = [
            "itinerary_slots": [["key": "1-morning", "day_number": 1, "date": "2027-04-01", "time_of_day": "morning", "activity": "Market"]],
            "itinerary_notes": ["1-morning": "Go early"],
        ]
        let text = PlanShareText.text(planName: "T", searchData: .null, selections: selections, shareURL: nil, labels: .english)
        #expect(text == "T\n\nItinerary\nDay 1, 2027-04-01\n  \u{2022} Morning \u{00B7} Market\n    Go early")
    }

    @Test func emptyPlanIsJustItsName() {
        #expect(PlanShareText.text(planName: "T", searchData: [:], selections: [:], shareURL: nil, labels: .english) == "T")
    }

    @Test func shareLinkIsAppendedOnlyForWebURLs() {
        let withLink = PlanShareText.text(planName: "T", searchData: [:], selections: [:], shareURL: "https://voyager.example/share/abc", labels: .english)
        #expect(withLink == "T\n\nView the plan: https://voyager.example/share/abc")
        #expect(PlanShareText.text(planName: "T", searchData: [:], selections: [:], shareURL: "javascript:alert(1)", labels: .english) == "T")
    }

    @Test func localisedLabelsAreUsed() {
        let labels = PlanShareText.Labels(
            flights: "F", hotel: "Hotel (de)", activities: "A", places: "P", walkingTours: "W", events: "E", sim: "S",
            gettingAround: "G", tips: "T", itinerary: "I", estimate: "Est", morning: "M", afternoon: "N", evening: "V",
            day: { "Tag \($0)" }, perNight: { "\($0) pro Nacht" }, viewOnline: { "Ansehen: \($0)" }, formatPrice: { "\($0) USD" })
        let text = PlanShareText.text(
            planName: "T", searchData: [:], selections: ["hotel": ["name": "Ritz"]], shareURL: nil, labels: labels)
        #expect(text.contains("\nHotel (de)\n  \u{2022} Ritz"))
    }

    @Test func flatFlightLegsAreListed() {
        let selections: JSONValue = ["flights": [
            ["airline": "AF", "flight_number": "AF12", "origin": "CDG", "destination": "FCO", "departure_date": "2027-04-01", "price_usd": 120],
        ]]
        let text = PlanShareText.text(planName: "T", searchData: [:], selections: selections, shareURL: nil, labels: .english)
        #expect(text.contains("AF AF12 \u{00B7} CDG \u{2192} FCO \u{00B7} 2027-04-01 \u{00B7} $120"))
    }

    @Test func timeOfDayUsesTheLocalisedLabelAndNeverTheRawValue() {
        let selections: JSONValue = ["itinerary_slots": [
            ["key": "1-evening", "day_number": 1, "time_of_day": "evening", "activity": "Dinner"],
            ["key": "1-late", "day_number": 1, "time_of_day": "late night", "activity": "Bar"],
        ]]
        let text = PlanShareText.text(planName: "T", searchData: [:], selections: selections, shareURL: nil, labels: .english)
        #expect(text.contains("\u{2022} Evening \u{00B7} Dinner"))
        #expect(!text.contains("late night"))
        #expect(text.contains("\u{2022} Bar"))
    }
}
