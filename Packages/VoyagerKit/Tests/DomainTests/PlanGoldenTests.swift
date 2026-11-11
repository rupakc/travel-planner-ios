import Testing
import Domain
import VoyagerModel

@Suite struct PlanGoldenTests {
    @Test(arguments: PlanGolden.cases("planHelpers"))
    func planHelpers(_ c: PlanGolden.Case) {
        let actual: JSONValue
        switch c.fn {
        case "sameFlight": actual = .bool(Selections.sameFlight(c.arg(0), c.arg(1)))
        case "countSelections": actual = .number(Double(Selections.count(c.arg(0))))
        case "computePlanCost": actual = .number(PlanCost.total(c.arg(0), searchData: c.arg(1)))
        case "computePlanCostBreakdown": actual = PlanCost.breakdown(c.arg(0), searchData: c.arg(1))
        case "getBudgetStatus":
            actual = PlanCost.budgetStatusDetail(cost: c.arg(0).double ?? 0, budget: c.arg(1), translate: PlanGolden.english)
            // The plain status agrees with the detail.
            #expect(PlanCost.budgetStatus(cost: c.arg(0).double ?? 0, budget: c.arg(1).double) == actual["status"].string)
        default:
            Issue.record("unhandled fn \(c.fn)")
            return
        }
        #expect(actual == c.output, "\(c.testDescription)")
    }

    @Test(arguments: PlanGolden.cases("stripLinkEvidence"))
    func stripLinkEvidence(_ c: PlanGolden.Case) {
        #expect(Selections.strippingLinkEvidence(c.arg(0)) == c.output, "\(c.testDescription)")
    }

    @Test func fixturesArePresent() {
        #expect(PlanGolden.cases("planHelpers").count > 30)
        #expect(PlanGolden.cases("stripLinkEvidence").count == 4)
    }

    @Test func itemLevelStripKeepsOtherKeys() {
        let item: JSONValue = ["name": "H", "link_verified": true, "link_checked": "x", "booking_url": "u"]
        #expect(Selections.stripLinkEvidence(item) == ["name": "H", "booking_url": "u"])
        #expect(Selections.stripLinkEvidence("plain") == "plain")
        #expect(Selections.stripLinkEvidence(["a": 1]) == ["a": 1])
    }

    @Test func budgetStatusPlain() {
        #expect(PlanCost.budgetStatus(cost: 100, budget: 200) == "under")
        #expect(PlanCost.budgetStatus(cost: 300, budget: 200) == "over")
        #expect(PlanCost.budgetStatus(cost: 200, budget: 200) == "under")
        #expect(PlanCost.budgetStatus(cost: 0, budget: 200) == nil)
        #expect(PlanCost.budgetStatus(cost: 10, budget: nil) == nil)
        #expect(PlanCost.budgetStatus(cost: 10, budget: 0) == nil)
    }

    @Test func emptySelectionsMatchTheWebConstant() {
        // EMPTY_SELECTIONS of frontend/src/utils/planHelpers.js
        let keys = ["flight", "flights", "hotel", "activities", "places_to_see", "walking_tours", "sim", "tips",
                    "getting_around", "events", "itinerary_notes", "itinerary_edits", "itinerary_slots", "itinerary_layout",
                    "packing_list"]
        #expect(Set(Selections.empty.object?.keys ?? [:].keys) == Set(keys))
        #expect(Selections.count(Selections.empty) == 0)
        for key in ["flights", "activities", "places_to_see", "walking_tours", "tips", "getting_around", "events", "itinerary_slots"] {
            #expect(Selections.empty[key] == [])
        }
        for key in ["itinerary_notes", "itinerary_edits"] { #expect(Selections.empty[key] == [:]) }
        for key in ["flight", "hotel", "sim", "itinerary_layout", "packing_list"] { #expect(Selections.empty[key] == nil) }
    }
}
