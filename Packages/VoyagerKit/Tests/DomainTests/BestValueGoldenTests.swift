import Testing
import Domain
import VoyagerModel

@Suite struct BestValueGoldenTests {
    @Test(arguments: PlanGolden.cases("bestValuePackage"))
    func golden(_ c: PlanGolden.Case) {
        let actual: JSONValue
        switch c.fn {
        case "buildBestValuePackage":
            actual = BestValuePackage.build(results: c.arg(0), searchData: c.arg(1), translate: PlanGolden.english) ?? .null
        case "applyPackage": actual = BestValuePackage.apply(c.arg(0), c.arg(1))
        case "isPackageApplied": actual = .bool(BestValuePackage.isApplied(c.arg(0), c.arg(1)))
        case "packageConflicts": actual = .array(BestValuePackage.conflicts(c.arg(0), c.arg(1)).map { .string($0) })
        default:
            Issue.record("unhandled fn \(c.fn)")
            return
        }
        #expect(actual == c.output, "\(c.testDescription)")
    }

    @Test func fixturesArePresent() {
        #expect(PlanGolden.cases("bestValuePackage").count > 80)
    }

    // The web's own `{ caps }` test vectors (budgetPlanner.test.js); predicates cannot go through the JSON generator.
    @Test func capsLimitTheHotelAndFlightPools() {
        let flight: JSONValue = ["airline": "Air", "flight_number": "A", "price_usd": 400, "source": "live",
                                 "outbound": ["airline": "Air", "flight_number": "A", "stops": 0, "duration_minutes": 600]]
        let dear: JSONValue = ["airline": "Air", "flight_number": "B", "price_usd": 410, "source": "live",
                               "outbound": ["airline": "Air", "flight_number": "B", "stops": 0, "duration_minutes": 100]]
        let results: JSONValue = [
            "flights": ["results": [flight, dear]],
            "hotels": ["results": [
                ["name": "Best", "star_rating": 3, "price_per_night_usd": 300, "review_score": 9],
                ["name": "Cheap", "star_rating": 3, "price_per_night_usd": 40, "review_score": 7],
            ]],
        ]
        let sd: JSONValue = ["departure_date": "2026-04-01", "return_date": "2026-04-08"]
        let free = BestValuePackage.build(results: results, searchData: sd)
        #expect(free?["selections"]["hotel"]["name"] == "Best")
        #expect(free?["selections"]["flight"]["flight_number"] == "B")

        let caps = BestValuePackage.Caps(hotel: { $0["name"] == "Cheap" }, flight: { $0["flight_number"] == "A" })
        let capped = BestValuePackage.build(results: results, searchData: sd, caps: caps)
        #expect(capped?["selections"]["hotel"]["name"] == "Cheap")
        #expect(capped?["selections"]["flight"]["flight_number"] == "A")

        // A pool with nothing allowed is left as is.
        let none = BestValuePackage.Caps(hotel: { _ in false }, flight: { _ in false })
        let unchanged = BestValuePackage.build(results: results, searchData: sd, caps: none)
        #expect(unchanged == free)
    }

    @Test func defaultTranslatorReturnsKeys() {
        let results: JSONValue = ["flights": ["results": [["price_usd": 100, "airline": "A", "flight_number": "1"]]]]
        let pkg = BestValuePackage.build(results: results, searchData: [:])
        #expect(pkg?["items"][0]["reason"] == "plan:best.reason.cheapestFare")
    }
}
