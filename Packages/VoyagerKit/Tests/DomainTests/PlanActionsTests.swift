import Testing
import Domain
import VoyagerModel

@Suite struct PlanActionsTests {
    private let s: JSONValue = [
        "flight": ["airline": "A", "price_usd": 100],
        "hotel": ["name": "H"],
        "activities": [["name": "a1"], ["name": "a2"]],
        "tips": [["title": "t1"]],
        "getting_around": [["name": "metro"]],
        "itinerary_slots": [["key": "1-morning"]],
        "sim": ["provider": "P"],
        "events": [["name": "e1"]],
    ]

    @Test func clearAllResetsToEmpty() {
        #expect(PlanActions.apply(s, action: "clear", field: "all", data: .null) == Selections.empty)
    }

    @Test func clearOnArrayFieldsGivesEmptyArray() {
        for field in ["activities", "tips", "getting_around", "itinerary_slots"] {
            let next = PlanActions.apply(s, action: "clear", field: field, data: .null)
            #expect(next[field] == [])
            #expect(next["hotel"] == s["hotel"])
        }
    }

    @Test func clearOnOtherFieldsGivesNull() {
        for field in ["flight", "hotel", "sim"] {
            let next = PlanActions.apply(s, action: "clear", field: field, data: .null)
            #expect(next[field] == .null)
            #expect(next["activities"] == s["activities"])
        }
        // events is not a chat array field: the web nulls it
        #expect(PlanActions.apply(s, action: "clear", field: "events", data: .null)["events"] == .null)
    }

    @Test func setReplacesTheField() {
        let next = PlanActions.apply(s, action: "set", field: "hotel", data: ["name": "New"])
        #expect(next["hotel"] == ["name": "New"])
        #expect(PlanActions.apply(s, action: "set", field: "activities", data: [["name": "z"]])["activities"] == [["name": "z"]])
        #expect(PlanActions.apply(s, action: "set", field: "sim", data: .null)["sim"] == .null)
    }

    @Test func addAppendsAndDedupesByTheRightKey() {
        let added = PlanActions.apply(s, action: "add", field: "activities", data: ["name": "a3"])
        #expect(added["activities"].array?.count == 3)
        #expect(PlanActions.apply(added, action: "add", field: "activities", data: ["name": "a3", "extra": 1]) == added)

        let tip = PlanActions.apply(s, action: "add", field: "tips", data: ["title": "t2"])
        #expect(tip["tips"].array?.count == 2)
        #expect(PlanActions.apply(s, action: "add", field: "tips", data: ["title": "t1"]) == s)
        // tips dedupe by title, not name
        #expect(PlanActions.apply(s, action: "add", field: "tips", data: ["name": "t1", "title": "other"])["tips"].array?.count == 2)

        #expect(PlanActions.apply(s, action: "add", field: "itinerary_slots", data: ["key": "1-morning"]) == s)
        #expect(PlanActions.apply(s, action: "add", field: "itinerary_slots", data: ["key": "1-evening"])["itinerary_slots"].array?.count == 2)
        #expect(PlanActions.apply(s, action: "add", field: "getting_around", data: ["name": "metro"]) == s)
    }

    @Test func addToMissingArrayCreatesIt() {
        let next = PlanActions.apply(["flight": .null], action: "add", field: "activities", data: ["name": "a"])
        #expect(next["activities"] == [["name": "a"]])
    }

    @Test func addOnSingleFieldsSetsThem() {
        #expect(PlanActions.apply(s, action: "add", field: "hotel", data: ["name": "N"])["hotel"] == ["name": "N"])
        #expect(PlanActions.apply(s, action: "add", field: "flight", data: ["airline": "B"])["flight"] == ["airline": "B"])
    }

    @Test func removeFiltersByTheRightKey() {
        #expect(PlanActions.apply(s, action: "remove", field: "activities", data: ["name": "a1"])["activities"] == [["name": "a2"]])
        #expect(PlanActions.apply(s, action: "remove", field: "tips", data: ["title": "t1"])["tips"] == [])
        #expect(PlanActions.apply(s, action: "remove", field: "itinerary_slots", data: ["key": "1-morning"])["itinerary_slots"] == [])
        #expect(PlanActions.apply(s, action: "remove", field: "getting_around", data: ["name": "nope"])["getting_around"] == s["getting_around"])
    }

    @Test func removeOnSingleFieldsNullsThem() {
        #expect(PlanActions.apply(s, action: "remove", field: "hotel", data: .null)["hotel"] == .null)
        #expect(PlanActions.apply(s, action: "remove", field: "sim", data: ["provider": "P"])["sim"] == .null)
    }

    @Test func unknownActionChangesNothing() {
        #expect(PlanActions.apply(s, action: "reorder", field: "activities", data: .null) == s)
    }

    @Test func addAndListRemoveIgnoreNonObjectData() {
        for data: JSONValue in [.null, "x", 3, [["name": "a1"]]] {
            #expect(PlanActions.apply(s, action: "add", field: "activities", data: data) == s)
            #expect(PlanActions.apply(s, action: "add", field: "hotel", data: data) == s)
            #expect(PlanActions.apply(s, action: "remove", field: "activities", data: data) == s)
        }
        // Removing a single field needs no data.
        #expect(PlanActions.apply(s, action: "remove", field: "hotel", data: .null)["hotel"] == .null)
    }

    @Test func plansAreValuesNotMutated() {
        let before = s
        _ = PlanActions.apply(s, action: "clear", field: "all", data: .null)
        #expect(s == before)
    }
}

@Suite struct SelectionsTests {
    private let f0: JSONValue = ["leg_index": 0, "price_usd": 100, "outbound": ["airline": "A", "flight_number": "1"]]
    private let f0b: JSONValue = ["leg_index": 0, "price_usd": 120, "outbound": ["airline": "B", "flight_number": "2"]]
    private let f1: JSONValue = ["leg_index": 1, "price_usd": 90, "outbound": ["airline": "C", "flight_number": "3"]]

    @Test func toggleListsAddAndRemoveByKey() {
        let cases: [(field: String, item: JSONValue)] = [
            ("activities", ["name": "a"]), ("places_to_see", ["name": "p"]), ("events", ["name": "e"]),
            ("getting_around", ["name": "g"]), ("tips", ["title": "t"]),
            ("walking_tours", ["name": "w", "url": "https://w/1"]), ("itinerary_slots", ["key": "1-morning", "activity": "x"]),
        ]
        for (field, item) in cases {
            let on = Selections.toggle(Selections.empty, field: field, item: item)
            #expect(on[field] == [item], "\(field)")
            #expect(Selections.contains(on, field: field, item: item))
            #expect(Selections.count(on) == 1)
            let off = Selections.toggle(on, field: field, item: item)
            #expect(off[field] == [], "\(field)")
            #expect(!Selections.contains(off, field: field, item: item))
        }
    }

    @Test func toggleDedupesWalkingToursByUrlNotName() {
        let a: JSONValue = ["name": "Same", "url": "u1"]
        let b: JSONValue = ["name": "Same", "url": "u2"]
        let s = Selections.toggle(Selections.toggle(Selections.empty, field: "walking_tours", item: a), field: "walking_tours", item: b)
        #expect(s["walking_tours"].array?.count == 2)
    }

    @Test func toggleSingleFieldsSet() {
        let s = Selections.toggle(Selections.empty, field: "hotel", item: ["name": "H"])
        #expect(s["hotel"] == ["name": "H"])
        #expect(Selections.contains(s, field: "hotel", item: ["name": "H"]))
        #expect(!Selections.contains(s, field: "hotel", item: ["name": "Other"]))
        // Picking another one replaces it.
        #expect(Selections.toggle(s, field: "hotel", item: ["name": "I"])["hotel"] == ["name": "I"])
        let sim = Selections.toggle(Selections.empty, field: "sim", item: ["provider": "P", "plan_name": "Q"])
        #expect(Selections.contains(sim, field: "sim", item: ["provider": "P", "plan_name": "Q"]))
        #expect(!Selections.contains(sim, field: "sim", item: ["provider": "P", "plan_name": "Z"]))
    }

    @Test func toggleFlightsKeepsOnePerLegSortedByLeg() {
        var s = Selections.toggle(Selections.empty, field: "flights", item: f1)
        s = Selections.toggle(s, field: "flights", item: f0)
        #expect(s["flights"] == [f0, f1])
        // Another fare on leg 0 replaces the first.
        s = Selections.toggle(s, field: "flights", item: f0b)
        #expect(s["flights"] == [f0b, f1])
        #expect(Selections.contains(s, field: "flights", item: f0b))
        #expect(!Selections.contains(s, field: "flights", item: f0))
        // The same fare again deselects it.
        s = Selections.toggle(s, field: "flights", item: f0b)
        #expect(s["flights"] == [f1])
        #expect(Selections.count(s) == 1)
    }

    @Test func toggleIsAValueOperation() {
        let before = Selections.empty
        _ = Selections.toggle(before, field: "activities", item: ["name": "a"])
        #expect(before == Selections.empty)
        // A missing list is treated as empty.
        #expect(Selections.toggle(["flight": .null], field: "tips", item: ["title": "t"])["tips"] == [["title": "t"]])
    }

    @Test func countsEveryField() {
        let s: JSONValue = [
            "flight": ["a": 1], "flights": [["a": 1]], "hotel": ["a": 1], "activities": [[:], [:]], "places_to_see": [[:]],
            "walking_tours": [[:]], "sim": ["a": 1], "getting_around": [[:]], "tips": [[:], [:]], "events": [[:]],
            "itinerary_slots": [[:]], "packing_list": ["categories": []],
        ]
        #expect(Selections.count(s) == 14)
        #expect(Selections.count(.null) == 0)
    }

    @Test func sameFlightIdentity() {
        #expect(Selections.sameFlight(f0, f0))
        #expect(!Selections.sameFlight(f0, f0b))
        #expect(!Selections.sameFlight(f0, .null))
        #expect(!Selections.sameFlight(.null, .null))
        let flat: JSONValue = ["airline": "X", "flight_number": "1", "price_usd": 50]
        #expect(Selections.sameFlight(flat, flat))
    }
}

@Suite struct PlanNameTests {
    /// SplitMix64: a small seeded generator (a constant generator would spin `randomElement` forever).
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let nouns = ["Adventure", "Escape", "Journey", "Odyssey", "Expedition", "Quest", "Voyage", "Getaway", "Trail", "Safari"]

    private func parts(_ name: String, destination: String) -> (adjective: String, noun: String)? {
        guard name.hasPrefix("The "), let range = name.range(of: " \(destination) ") else { return nil }
        return (String(name[name.index(name.startIndex, offsetBy: 4)..<range.lowerBound]), String(name[range.upperBound...]))
    }

    @Test func themedByFirstInterest() {
        for _ in 0..<30 {
            let name = PlanName.generate(destination: "Tokyo", interests: ["food", "history"], departureDate: "2026-04-01")
            let p = parts(name, destination: "Tokyo")
            #expect(["Foodie", "Culinary", "Gourmet", "Tasty"].contains(p?.adjective ?? ""), "\(name)")
            #expect(Self.nouns.contains(p?.noun ?? ""), "\(name)")
        }
    }

    @Test func seasonalWhenNoKnownInterest() {
        let cases: [(date: String, words: [String])] = [
            ("2026-04-01", ["Blossom", "Fresh", "Springtime"]), ("2026-07-15", ["Sunny", "Sizzling", "Tropical"]),
            ("2026-10-31", ["Golden", "Autumn", "Amber"]), ("2026-01-02", ["Frosty", "Cozy", "Snowbound"]),
            ("2026-12-25", ["Frosty", "Cozy", "Snowbound"]), ("2026-03-01", ["Blossom", "Fresh", "Springtime"]),
            ("2026-11-30", ["Golden", "Autumn", "Amber"]), ("not a date", ["Frosty", "Cozy", "Snowbound"]),
        ]
        for (date, words) in cases {
            for interests in [[], ["unknown"]] {
                let name = PlanName.generate(destination: "Rome", interests: interests, departureDate: date)
                #expect(words.contains(parts(name, destination: "Rome")?.adjective ?? ""), "\(date): \(name)")
            }
        }
    }

    @Test func genericWithoutInterestsOrDate() {
        for date in [nil, ""] as [String?] {
            let name = PlanName.generate(destination: "Rome", departureDate: date)
            #expect(["Grand", "Dreamy", "Cosmic", "Wanderlust"].contains(parts(name, destination: "Rome")?.adjective ?? ""), "\(name)")
        }
    }

    @Test func emptyDestinationIsMystery() {
        #expect(PlanName.generate(destination: "").contains(" Mystery "))
    }

    @Test func deterministicWithASeededGenerator() {
        var one = Seeded(state: 42)
        var two = Seeded(state: 42)
        let first = PlanName.generate(destination: "Oslo", interests: ["art"], departureDate: nil, using: &one)
        #expect(first == PlanName.generate(destination: "Oslo", interests: ["art"], departureDate: nil, using: &two))
        let p = parts(first, destination: "Oslo")
        #expect(["Artsy", "Creative", "Gallery", "Canvas"].contains(p?.adjective ?? ""))
        #expect(Self.nouns.contains(p?.noun ?? ""))
        // Different seeds reach different names.
        var names = Set<String>()
        for seed in 0..<40 as Range<UInt64> {
            var g = Seeded(state: seed)
            names.insert(PlanName.generate(destination: "Oslo", interests: ["art"], departureDate: nil, using: &g))
        }
        #expect(names.count > 10)
    }
}
