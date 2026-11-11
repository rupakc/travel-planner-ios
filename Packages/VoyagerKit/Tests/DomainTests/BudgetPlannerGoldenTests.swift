import Testing
import Domain
import VoyagerModel

@Suite struct BudgetPlannerGoldenTests {
    @Test(arguments: PlanGolden.cases("budgetPlanner"))
    func golden(_ c: PlanGolden.Case) {
        let actual: JSONValue
        switch c.fn {
        case "tripNights": actual = .number(BudgetPlanner.tripNights(c.arg(0)))
        case "flightKey": actual = .string(BudgetPlanner.flightKey(c.arg(0)))
        case "defaultAllocation":
            actual = BudgetPlanner.defaultAllocation(c.arg(0), c.arg(1))?.json ?? .null
        case "reallocate":
            actual = BudgetPlanner.reallocate(
                .init(json: c.arg(0)), key: c.arg(1).string ?? "", value: c.arg(2), total: c.args.count > 3 ? c.arg(3).double : nil).json
        case "withTotal":
            actual = BudgetPlanner.withTotal(.init(json: c.arg(0)), total: c.arg(1)).json
        case "fitResults":
            actual = BudgetPlanner.fitResults(c.arg(0), .init(json: c.arg(1)), c.arg(2)).json
        default:
            Issue.record("unhandled fn \(c.fn)")
            return
        }
        #expect(actual == c.output, "\(c.testDescription)")
    }

    @Test func fixturesArePresent() {
        #expect(PlanGolden.cases("budgetPlanner").count > 50)
    }

    @Test func plannerKeys() {
        #expect(BudgetPlanner.keys == ["flights", "stay", "activities"])
    }

    @Test func capsFromFitKeepOnlyWhatFits() {
        let results: JSONValue = [
            "flights": ["results": [
                ["airline": "Air", "flight_number": "A", "price_usd": 400],
                ["airline": "Air", "flight_number": "B", "price_usd": 900],
            ]],
            "hotels": ["results": [
                ["name": "Fits", "price_per_night_usd": 50, "star_rating": 3, "review_score": 8],
                ["name": "Over", "price_per_night_usd": 500, "star_rating": 3, "review_score": 9],
            ]],
        ]
        let sd: JSONValue = ["departure_date": "2026-04-01", "return_date": "2026-04-08", "budget_usd": 3000]
        let allocation = BudgetPlanner.Allocation(flights: 500, stay: 400, activities: 0, other: 2100)
        let fit = BudgetPlanner.fitResults(results, allocation, sd)
        #expect(fit.hotels.fits == ["Fits"])
        let caps = BudgetPlanner.capsFromFit(fit)
        #expect(caps.hotel?(["name": "Fits"]) == true)
        #expect(caps.hotel?(["name": "Over"]) == false)
        #expect(caps.flight?(["airline": "Air", "flight_number": "A", "price_usd": 400]) == true)
        #expect(caps.flight?(["airline": "Air", "flight_number": "B", "price_usd": 900]) == false)
        let pkg = BestValuePackage.build(results: results, searchData: sd, caps: caps)
        #expect(pkg?["selections"]["hotel"]["name"] == "Fits")
        #expect(pkg?["selections"]["flight"]["flight_number"] == "A")
    }

    @Test func allocationSubscriptAndSum() {
        var a = BudgetPlanner.Allocation(flights: 1, stay: 2, activities: 3, other: 4)
        #expect(a.sum == 10)
        a["stay"] = 20
        #expect(a.stay == 20 && a["other"] == 4 && a["flights"] == 1 && a["activities"] == 3)
        #expect(BudgetPlanner.Allocation(json: a.json) == a)
    }
}
