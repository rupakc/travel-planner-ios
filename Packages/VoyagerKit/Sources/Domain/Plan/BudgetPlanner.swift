import Foundation
import VoyagerModel

/// Budget planner (port of `budgetPlanner.js`): splits the trip budget into Flights / Stay / Activities /
/// Everything else and checks already-loaded results against each share. Units follow the My Plan drawer:
/// flight `price_usd` per person, hotel nightly x nights, activity `price_usd`. Agent prices are LLM output,
/// so any non-finite or non-positive price is "unknown": never fits, never "over".
public enum BudgetPlanner {
    public static let keys = ["flights", "stay", "activities"]

    static let activityShare = 0.15
    static let defaultNights = 7.0
    static let step = 10.0
    static let epsilon = 1e-9

    /// The four shares; they always sum to the budget.
    public struct Allocation: Sendable, Hashable {
        public var flights: Double
        public var stay: Double
        public var activities: Double
        public var other: Double

        public init(flights: Double, stay: Double, activities: Double, other: Double) {
            self.flights = flights
            self.stay = stay
            self.activities = activities
            self.other = other
        }

        /// From `{flights, stay, activities, other}` (missing values are 0).
        public init(json: JSONValue) {
            self.init(
                flights: json["flights"].double ?? 0, stay: json["stay"].double ?? 0,
                activities: json["activities"].double ?? 0, other: json["other"].double ?? 0)
        }

        public var json: JSONValue {
            ["flights": .number(flights), "stay": .number(stay), "activities": .number(activities), "other": .number(other)]
        }

        public var sum: Double { flights + stay + activities + other }

        public subscript(key: String) -> Double {
            get {
                switch key {
                case "flights": return flights
                case "stay": return stay
                case "activities": return activities
                default: return other
                }
            }
            set {
                switch key {
                case "flights": flights = newValue
                case "stay": stay = newValue
                case "activities": activities = newValue
                default: other = newValue
                }
            }
        }
    }

    /// What fits a share: names (hotels) or `flightKey`s (flights), in result order.
    public struct Fit: Sendable, Hashable {
        public var fits: [String] = []
        public var over: [String] = []
        public var count: Int { fits.count }
        public var total: Int { fits.count + over.count }

        public var json: JSONValue {
            ["fits": .array(fits.map { .string($0) }), "over": .array(over.map { .string($0) }),
             "count": .number(Double(count)), "total": .number(Double(total))]
        }
    }

    public struct FitResult: Sendable, Hashable {
        public var hotels: Fit
        public var flights: Fit
        public var picked: [String]
        public var spent: Double
        public var nights: Double

        public var json: JSONValue {
            ["hotels": hotels.json, "flights": flights.json,
             "activities": ["picked": .array(picked.map { .string($0) }), "spent": .number(spent)],
             "nights": .number(nights)]
        }
    }

    // MARK: Trip helpers

    /// Nights from the dates (minimum 1; 7 without usable dates).
    public static func tripNights(_ searchData: JSONValue?) -> Double {
        guard let sd = searchData, sd["departure_date"].isTruthy, sd["return_date"].isTruthy else { return defaultNights }
        let span = (PlanJS.ms(sd["return_date"]) - PlanJS.ms(sd["departure_date"])) / PlanJS.dayMs
        return span.isFinite ? max(1, PlanJS.round(span)) : defaultNights
    }

    /// Same fields as `Selections.sameFlight`, as a set-friendly string.
    public static func flightKey(_ fare: JSONValue?) -> String {
        let fare = fare ?? .null
        return [
            PlanJS.coalesce(fare["leg_index"], ""), fare["price_usd"],
            PlanJS.coalesce(fare["outbound"]["airline"], fare["airline"]),
            PlanJS.coalesce(fare["outbound"]["flight_number"], fare["flight_number"]),
        ].map { PlanJS.string($0) }.joined(separator: "|")
    }

    private static func flightLegs(_ section: JSONValue) -> [[JSONValue]] {
        guard section.isTruthy, !section["error"].isTruthy else { return [] }
        if let legs = section["legs"].array, !legs.isEmpty {
            return legs.map { ($0["results"].array ?? []).filter(\.isTruthy) }
        }
        return [PlanJS.listOf(section)]
    }

    private static func cheapestFare(_ fares: [JSONValue]) -> Double? {
        fares.compactMap { PlanJS.positive($0["price_usd"]) }.min()
    }

    private static func ceilStep(_ value: Double) -> Double { ((value - epsilon) / step).rounded(.up) * step }
    private static func floorStep(_ value: Double) -> Double { ((value + epsilon) / step).rounded(.down) * step }
    private static func roundStep(_ value: Double) -> Double { PlanJS.round(value / step) * step }
    private static func fits(_ amount: Double, _ share: Double) -> Bool { amount <= share + epsilon }

    // MARK: Allocation

    /// Defaults: cheapest fare(s), median hotel x nights (both rounded up to $10), 15 % activities, the rest
    /// "other". `nil` without a positive budget.
    public static func defaultAllocation(_ searchData: JSONValue?, _ results: JSONValue?) -> Allocation? {
        guard let budget = PlanJS.positive(searchData?["budget_usd"]) else { return nil }
        let total = PlanJS.round(budget)
        let input = results ?? .null
        let legCheapest = flightLegs(input["flights"]).compactMap(cheapestFare)
        let flights = legCheapest.isEmpty ? 0 : ceilStep(legCheapest.reduce(0, +))
        let nightlies = PlanJS.listOf(input["hotels"]).compactMap { PlanJS.positive($0["price_per_night_usd"]) }
        let stay = nightlies.isEmpty ? 0 : ceilStep(PlanJS.median(nightlies) * tripNights(searchData))
        return defaultsWithin(flights: flights, stay: stay, activities: roundStep(total * activityShare), total: total)
    }

    /// Defaults that overshoot the total give way in order: activities (to 0), then stay (to 0); flights shrink
    /// only when the fare alone exceeds the total. Shrunk shares snap down to the $10 grid.
    private static func defaultsWithin(flights: Double, stay: Double, activities: Double, total: Double) -> Allocation {
        let flightsShare = min(flights, total)
        let stayShare = min(stay, floorStep(total - flightsShare))
        let activitiesShare = min(activities, floorStep(total - flightsShare - stayShare))
        return Allocation(
            flights: flightsShare, stay: stayShare, activities: activitiesShare,
            other: total - flightsShare - stayShare - activitiesShare)
    }

    /// Move one category; the difference comes from / goes to `other`, clamped so `other` never drops below 0.
    public static func reallocate(_ allocation: Allocation, key: String, value: JSONValue, total: Double? = nil) -> Allocation {
        guard keys.contains(key) else { return allocation }
        let total = total ?? allocation.sum
        let rest = keys.filter { $0 != key }.reduce(0.0) { $0 + allocation[$1] }
        let clamped = min(max(0, PlanJS.round(PlanJS.num(value) ?? 0)), max(0, total - rest))
        var next = allocation
        next[key] = clamped
        next.other = total - rest - clamped
        return next
    }

    /// The user edited the total: `other` absorbs the change first, then the three shares scale down.
    public static func withTotal(_ allocation: Allocation, total: JSONValue) -> Allocation {
        let limit = max(0, PlanJS.round(PlanJS.num(total) ?? 0))
        var parts = allocation
        let used = allocation.flights + allocation.stay + allocation.activities
        if used > limit {
            let scale = limit / used
            for key in keys { parts[key] = (parts[key] * scale).rounded(.down) }
        }
        parts.other = limit - (parts.flights + parts.stay + parts.activities)
        return parts
    }

    // MARK: Fit

    private static func append(_ list: inout [String], _ value: String) {
        if !list.contains(value) { list.append(value) }
    }

    private static func fitFlights(_ section: JSONValue, _ share: Double) -> Fit {
        var fit = Fit()
        let legs = flightLegs(section)
        let multi = !(section["legs"].array ?? []).isEmpty
        let cheapest = legs.map(cheapestFare)
        let cheapestTotal = cheapest.reduce(0.0) { $0 + ($1 ?? 0) }
        for (i, fares) in legs.enumerated() {
            // A leg with no priced fare is unknown as a whole.
            guard let legCheapest = cheapest[i] else { continue }
            let cap = multi ? (share * legCheapest) / cheapestTotal : share
            for fare in fares {
                guard let price = PlanJS.positive(fare["price_usd"]) else { continue }
                // JS Sets are keyed by value: a key in `fits` is never added to `over` twice, but may be in both.
                if fits(price, cap) { append(&fit.fits, flightKey(fare)) } else { append(&fit.over, flightKey(fare)) }
            }
        }
        return fit
    }

    private static func fitHotels(_ section: JSONValue, _ share: Double, _ nights: Double) -> Fit {
        var fit = Fit()
        for hotel in PlanJS.listOf(section) {
            guard hotel["name"].isTruthy, let nightly = PlanJS.positive(hotel["price_per_night_usd"]) else { continue }
            let name = PlanJS.string(hotel["name"])
            if fits(nightly * nights, share) { append(&fit.fits, name) } else { append(&fit.over, name) }
        }
        return fit
    }

    private static func pickActivities(_ section: JSONValue, _ share: Double) -> (picked: [String], spent: Double) {
        struct Entry { var activity: JSONValue; var i: Int; var price: Double; var score: Double? }
        let priced = PlanJS.listOf(section).enumerated().compactMap { i, activity -> Entry? in
            guard activity["name"].isTruthy, let price = PlanJS.num(activity["price_usd"]), price >= 0 else { return nil }
            return Entry(activity: activity, i: i, price: price, score: PlanJS.num(activity["similarity_score"]))
        }
        let sorted = PlanJS.sortBy(priced, [{ x, y in
            if x.score != y.score {
                guard let xs = x.score else { return 1 }
                guard let ys = y.score else { return -1 }
                return ys - xs
            }
            let byPrice = x.price - y.price
            return byPrice != 0 ? byPrice : Double(x.i - y.i)
        }])
        var picked: [String] = []
        var spent = 0.0
        for entry in sorted {
            let name = PlanJS.string(entry.activity["name"])
            if entry.price == 0 {
                append(&picked, name)
            } else if fits(spent + entry.price, share) {
                append(&picked, name)
                spent += entry.price
            }
        }
        return (picked, PlanJS.round(spent * 100) / 100)
    }

    /// Which hotels, fares and activities fit the shares.
    public static func fitResults(_ results: JSONValue?, _ allocation: Allocation, _ searchData: JSONValue?) -> FitResult {
        let input = results ?? .null
        let nights = tripNights(searchData)
        let activities = pickActivities(input["activities"], allocation.activities)
        return FitResult(
            hotels: fitHotels(input["hotels"], allocation.stay, nights), flights: fitFlights(input["flights"], allocation.flights),
            picked: activities.picked, spent: activities.spent, nights: nights)
    }

    /// Predicates for `BestValuePackage.build`'s `caps`.
    public static func capsFromFit(_ fit: FitResult) -> BestValuePackage.Caps {
        let hotelFits = Set(fit.hotels.fits)
        let flightFits = Set(fit.flights.fits)
        return BestValuePackage.Caps(
            hotel: { hotelFits.contains(PlanJS.string($0["name"])) },
            flight: { flightFits.contains(flightKey($0)) })
    }
}
