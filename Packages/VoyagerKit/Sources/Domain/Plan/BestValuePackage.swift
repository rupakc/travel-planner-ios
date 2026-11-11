import Foundation
import VoyagerModel

/// Deterministic "best-value package" over streamed search results (port of `bestValuePackage.js`).
/// Every pick is a real listed item; agent output is LLM-driven, so every number is coerced and anything
/// non-finite counts as unknown. The result is a `JSONValue` `{items, selections, total, budget}`:
/// each item is `{type, item, reason, city?}` and `reason` is the text produced by `translate`.
public enum BestValuePackage {
    /// Budget-planner limits on the hotel and flight pools; a pool with nothing allowed is left as is.
    public struct Caps: Sendable {
        public var hotel: (@Sendable (JSONValue) -> Bool)?
        public var flight: (@Sendable (JSONValue) -> Bool)?
        public init(hotel: (@Sendable (JSONValue) -> Bool)? = nil, flight: (@Sendable (JSONValue) -> Bool)? = nil) {
            self.hotel = hotel
            self.flight = flight
        }
    }

    static let flightPriceWindow = 1.15
    static let activityPriceFloor = 30.0
    static let minTimeSavedMinutes = 90.0
    static let minCheapHotelReview = 7.0
    static let maxActivitiesPerCity = 2, maxActivities = 4, maxWalkingTours = 3, maxPlacesPerCity = 2, maxPlaces = 4

    typealias Pick = (item: JSONValue, reason: JSONValue)

    struct Leg {
        let item: JSONValue
        let reason: JSONValue
        let city: JSONValue?
    }

    struct FlightPicks {
        var single: Pick?
        var legs: [Leg]
    }

    // MARK: Builder

    public static func build(
        results: JSONValue, searchData: JSONValue, caps: Caps? = nil,
        translate tt: @escaping PlanText = planKeyText, locale: Locale = Locale(identifier: "en_US")
    ) -> JSONValue? {
        let ctx = Context(tt: tt, locale: locale)
        let flights = ctx.pickFlights(results["flights"], caps?.flight)
        let first = firstStop(results, searchData)
        let hotelCands = capped(hotelCandidates(results["hotels"], first), caps?.hotel)
        var hotel = ctx.pickHotel(hotelCands, first)
        if flights.single == nil && flights.legs.isEmpty && hotel == nil { return nil }

        let activities = ctx.pickActivities(results["activities"])
        let tours = ctx.pickWalkingTours(results["walking_tours"])
        let places = ctx.pickPlaces(results["places_to_see"])
        let sim = ctx.pickSim(results["sim"], searchData)

        func selectionsFor(_ chosenHotel: Pick?) -> JSONValue {
            [
                "flight": flights.single?.item ?? .null,
                "flights": .array(flights.legs.map(\.item)),
                "hotel": chosenHotel?.item ?? .null,
                "activities": .array(activities.map(\.item)),
                "walking_tours": .array(tours.map(\.item)),
                "places_to_see": .array(places.map(\.item)),
                "sim": sim?.item ?? .null,
            ]
        }

        var selections = selectionsFor(hotel)
        var total = PlanCost.total(selections, searchData: searchData)

        // Budget fit: only the hotel is ever swapped.
        if let current = hotel, let cheaper = cheaperHotel(than: current, among: hotelCands, total: total, searchData: searchData) {
            hotel = (cheaper, .string(tt("plan:best.reason.cheaperStay", [:])))
            selections = selectionsFor(hotel)
            total = PlanCost.total(selections, searchData: searchData)
        }

        var items: [JSONValue] = []
        func add(_ type: String, _ pick: Pick, city: JSONValue? = nil) {
            var entry: [String: JSONValue] = ["type": .string(type), "item": pick.item, "reason": pick.reason]
            if let city { entry["city"] = city }
            items.append(.object(entry))
        }
        if let single = flights.single { add("flight", single) }
        for leg in flights.legs { add("flights", Pick(item: leg.item, reason: leg.reason), city: leg.city) }
        if let hotel { add("hotel", hotel) }
        for activity in activities { add("activities", activity, city: activity.item.object?["city"]) }
        for tour in tours { add("walking_tours", tour, city: tour.item.object?["city"]) }
        for place in places { add("places_to_see", place, city: place.item.object?["city"]) }
        if let sim { add("sim", sim) }

        return [
            "items": .array(items),
            "selections": selections,
            "total": .number(total),
            "budget": PlanCost.budgetStatusDetail(cost: total, budget: searchData["budget_usd"], translate: tt, locale: locale),
        ]
    }

    /// The cheapest decently reviewed hotel when the package is over budget and that hotel costs less.
    private static func cheaperHotel(than current: Pick, among cands: [JSONValue], total: Double, searchData: JSONValue) -> JSONValue? {
        guard let budget = PlanJS.num(searchData["budget_usd"]), budget > 0, total > budget else { return nil }
        func cost(_ hotel: JSONValue) -> Double { PlanCost.total(["hotel": hotel], searchData: searchData) }
        let decent = cands.filter { (review($0) ?? minCheapHotelReview) >= minCheapHotelReview }
        guard let cheaper = PlanJS.sortBy(decent, [PlanJS.byAsc(cost)]).first, cost(cheaper) < cost(current.item) else { return nil }
        return cheaper
    }

    // MARK: Apply / compare

    private static var identity: [(key: String, same: (JSONValue, JSONValue) -> Bool)] {
        [("activities", keyed("name")), ("places_to_see", keyed("name")), ("walking_tours", keyed("url"))]
    }

    private static func keyed(_ key: String) -> (JSONValue, JSONValue) -> Bool {
        { lhs, rhs in !lhs[key].isNull && lhs[key] == rhs[key] }
    }

    private static func sameHotel(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool { keyed("name")(lhs, rhs) }

    private static func sameSim(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        lhs.isTruthy && rhs.isTruthy && (!lhs["provider"].isNull || !lhs["plan_name"].isNull)
            && lhs["provider"] == rhs["provider"] && lhs["plan_name"] == rhs["plan_name"]
    }

    /// Add the package to the selections: its flight/hotel/SIM replace the current ones, its legs replace the
    /// same legs, its list items are appended unless already there.
    public static func apply(_ selections: JSONValue, _ pkg: JSONValue) -> JSONValue {
        var next = selections.object ?? [:]
        let pack = pkg["selections"]
        if pack["flight"].isTruthy { next["flight"] = pack["flight"] }
        let packLegs = pack["flights"].array ?? []
        if !packLegs.isEmpty {
            let covered = Set(packLegs.map { $0["leg_index"] })
            let kept = (selections["flights"].array ?? []).filter { !covered.contains($0["leg_index"]) }
            next["flights"] = .array(PlanJS.sortBy(kept + packLegs, [{ lhs, rhs in
                (lhs["leg_index"].double ?? 0) - (rhs["leg_index"].double ?? 0)
            }]))
        }
        if pack["hotel"].isTruthy { next["hotel"] = pack["hotel"] }
        if pack["sim"].isTruthy { next["sim"] = pack["sim"] }
        for (key, same) in identity {
            let picked = pack[key].array ?? []
            if picked.isEmpty { continue }
            let existing = selections[key].array ?? []
            var added: [JSONValue] = []
            for x in picked where !(existing + added).contains(where: { same($0, x) }) { added.append(x) }
            next[key] = .array(existing + added)
        }
        return .object(next)
    }

    /// Whether every pick of the package is already in the selections.
    public static func isApplied(_ current: JSONValue, _ pkg: JSONValue) -> Bool {
        let pack = pkg["selections"]
        if pack["flight"].isTruthy && !Selections.sameFlight(current["flight"], pack["flight"]) { return false }
        let existingLegs = current["flights"].array ?? []
        if !(pack["flights"].array ?? []).allSatisfy({ fare in existingLegs.contains { Selections.sameFlight($0, fare) } }) { return false }
        if pack["hotel"].isTruthy && !sameHotel(current["hotel"], pack["hotel"]) { return false }
        if pack["sim"].isTruthy && !sameSim(current["sim"], pack["sim"]) { return false }
        return identity.allSatisfy { key, same in
            (pack[key].array ?? []).allSatisfy { x in (current[key].array ?? []).contains { same($0, x) } }
        }
    }

    /// Labels (`"flight"`, `"hotel"`, `"SIM"`) of picks the user already made that applying would replace.
    public static func conflicts(_ current: JSONValue, _ pkg: JSONValue) -> [String] {
        let pack = pkg["selections"]
        var out: [String] = []
        let packLegs = pack["flights"].array ?? []
        let existingLegs = current["flights"].array ?? []
        let singleClash = pack["flight"].isTruthy && current["flight"].isTruthy
            && !Selections.sameFlight(current["flight"], pack["flight"])
        let flightClash = singleClash
            || packLegs.contains { fare in
                existingLegs.contains { $0["leg_index"] == fare["leg_index"] && !Selections.sameFlight($0, fare) }
            }
        if flightClash { out.append("flight") }
        if pack["hotel"].isTruthy && current["hotel"].isTruthy && !sameHotel(current["hotel"], pack["hotel"]) { out.append("hotel") }
        if pack["sim"].isTruthy && current["sim"].isTruthy && !sameSim(current["sim"], pack["sim"]) { out.append("SIM") }
        return out
    }

    // MARK: Pools

    /// Keep only items the caps allow; if none are allowed, keep them all.
    private static func capped(_ items: [JSONValue], _ allow: (@Sendable (JSONValue) -> Bool)?) -> [JSONValue] {
        guard let allow else { return items }
        let kept = items.filter(allow)
        return kept.isEmpty ? items : kept
    }

    private static func review(_ hotel: JSONValue) -> Double? { PlanJS.num(hotel["review_score"]) }
    private static func nightly(_ hotel: JSONValue) -> Double? { PlanJS.num(hotel["price_per_night_usd"]) }

    /// Multi-city only: the first stop. The search form stores IATA codes in `destinations`, so the flight
    /// leg's destination name is preferred.
    private static func firstStop(_ results: JSONValue, _ searchData: JSONValue) -> JSONValue? {
        guard (searchData["destinations"].array?.count ?? 0) > 1 else { return nil }
        if let to = results["flights"]["legs"][0]["to"].string,
           !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .string(to) }
        return searchData["destinations"][0]
    }

    private static func hotelCandidates(_ section: JSONValue, _ first: JSONValue?) -> [JSONValue] {
        var cands = PlanJS.listOf(section).filter { $0["name"].isTruthy && (nightly($0) ?? 0) > 0 }
        if let first, first.isTruthy {
            let key = PlanJS.cityKey(first)
            var inCity = cands.filter { PlanJS.cityKey($0["city"]) == key }
            if inCity.isEmpty, let tagged = cands.first(where: { !PlanJS.cityKey($0["city"]).isEmpty }) {
                let taggedKey = PlanJS.cityKey(tagged["city"])
                inCity = cands.filter { PlanJS.cityKey($0["city"]) == taggedKey }
            }
            if !inCity.isEmpty { cands = inCity }
        }
        return cands
    }

    private static func takePerCity(_ sorted: [JSONValue], perCity: Int, total: Int) -> [JSONValue] {
        var counts: [String: Int] = [:]
        var out: [JSONValue] = []
        for x in sorted {
            let key = PlanJS.cityKey(x["city"])
            if counts[key, default: 0] >= perCity { continue }
            counts[key, default: 0] += 1
            out.append(x)
            if out.count >= total { break }
        }
        return out
    }

    private static func flightPrice(_ fare: JSONValue) -> Double? { PlanJS.num(fare["price_usd"]) }
    private static func flightStops(_ fare: JSONValue) -> Double {
        (PlanJS.num(PlanJS.coalesce(fare["outbound"]["stops"], fare["stops"])) ?? 0) + (PlanJS.num(fare["return"]["stops"]) ?? 0)
    }
    private static func flightDuration(_ fare: JSONValue) -> Double? {
        guard let out = PlanJS.num(PlanJS.coalesce(fare["outbound"]["duration_minutes"], fare["duration_minutes"])) else { return nil }
        return out + (PlanJS.num(fare["return"]["duration_minutes"]) ?? 0)
    }

    /// Per-call state: the translator and number formatting.
    private struct Context {
        let tt: PlanText
        let locale: Locale

        func text(_ key: String, _ params: [String: String] = [:]) -> JSONValue {
            .string(tt("plan:\(key)", params))
        }

        func money(_ amount: Double) -> String { PlanFormat.usd0(amount, locale: locale) }

        func duration(_ mins: Double) -> String {
            let total = PlanJS.round(mins)
            let hours = (total / 60).rounded(.down)
            let minutes = total - hours * 60
            var parts: [String] = []
            if hours != 0 { parts.append(tt("plan:util.hours", ["n": PlanJS.numberString(hours)])) }
            if minutes != 0 { parts.append(tt("plan:util.minutes", ["n": PlanJS.numberString(minutes)])) }
            return parts.joined(separator: " ")
        }

        func pickFlight(_ flights: [JSONValue], _ allow: (@Sendable (JSONValue) -> Bool)?) -> Pick? {
            var cands = BestValuePackage.capped(flights.filter { (flightPrice($0) ?? 0) > 0 }, allow)
            if cands.contains(where: { $0["source"] != "estimate" }) { cands = cands.filter { $0["source"] != "estimate" } }
            if cands.isEmpty { return nil }
            let cheapestOverall = PlanJS.sortBy(cands, [PlanJS.byAsc(flightPrice), PlanJS.byAsc { flightStops($0) }])[0]
            let cheapestPrice = flightPrice(cheapestOverall) ?? 0
            let pool = cands.filter { (flightPrice($0) ?? 0) <= cheapestPrice * flightPriceWindow }
            let fewest = pool.map(flightStops).min() ?? 0
            let group = pool.filter { flightStops($0) == fewest }
            let base = PlanJS.sortBy(group, [PlanJS.byAsc(flightPrice), PlanJS.byAsc(flightDuration)])[0]
            let baseDuration = flightDuration(base)
            let faster = group.filter { fare in
                guard let minutes = flightDuration(fare), let bd = baseDuration else { return false }
                return (flightPrice(fare) ?? 0) > (flightPrice(base) ?? 0) && bd - minutes >= minTimeSavedMinutes
            }
            let best = faster.isEmpty ? base : PlanJS.sortBy(faster, [PlanJS.byAsc(flightDuration), PlanJS.byAsc(flightPrice)])[0]
            let extra = PlanJS.round((flightPrice(best) ?? 0) - cheapestPrice)
            var reason = text("best.reason.cheapestFare")
            if extra > 0 {
                if flightStops(best) < flightStops(cheapestOverall) {
                    reason = text("best.reason.fewerStops", ["amount": money(extra)])
                } else {
                    let saved = (baseDuration ?? 0) - (flightDuration(best) ?? 0)
                    reason = text("best.reason.saves", ["time": duration(saved), "amount": money(extra)])
                }
            }
            return (best, reason)
        }

        func pickFlights(_ section: JSONValue, _ allow: (@Sendable (JSONValue) -> Bool)?)
            -> FlightPicks {
            guard section.isTruthy, !section["error"].isTruthy else { return FlightPicks(single: nil, legs: []) }
            guard let sectionLegs = section["legs"].array, !sectionLegs.isEmpty else {
                return FlightPicks(single: pickFlight(PlanJS.listOf(section), allow), legs: [])
            }
            var legs: [Leg] = []
            for (i, leg) in sectionLegs.enumerated() {
                let results = (leg["results"].array ?? []).filter(\.isTruthy)
                guard let pick = pickFlight(results, allow) else { continue }
                let legIndex = PlanJS.coalesce(pick.item["leg_index"], PlanJS.coalesce(leg["leg_index"], .number(Double(i))))
                let item = pick.item["leg_index"] == legIndex ? pick.item : PlanJS.set(pick.item, "leg_index", legIndex)
                let city = PlanJS.coalesce(pick.item["city"], leg["to"])
                let cityOrNone: JSONValue? = city.isNull ? Optional<JSONValue>.none : city
                legs.append(Leg(item: item, reason: pick.reason, city: cityOrNone))
            }
            legs = PlanJS.sortBy(legs, [{ lhs, rhs in (lhs.item["leg_index"].double ?? 0) - (rhs.item["leg_index"].double ?? 0) }])
            return FlightPicks(single: nil, legs: legs)
        }

        func pickHotel(_ cands: [JSONValue], _ first: JSONValue?) -> Pick? {
            if cands.isEmpty { return nil }
            func stars(_ hotel: JSONValue) -> Double? { PlanJS.num(hotel["star_rating"]).map(PlanJS.round) }
            var pool = cands.filter { stars($0) == 3 }
            if pool.isEmpty { pool = cands.filter { stars($0) == 4 } }
            if pool.isEmpty { pool = cands }
            let best = PlanJS.sortBy(pool, [PlanJS.byDesc(review), PlanJS.byAsc(nightly)])[0]
            let starCount = stars(best)
            let label: String
            if starCount == 3 {
                label = tt("plan:best.reason.midRange", [:])
            } else if let starCount, starCount > 0 {
                label = tt("plan:best.reason.starsBest", ["stars": PlanJS.numberString(starCount)])
            } else {
                label = tt("plan:best.reason.bestReviewed", [:])
            }
            var city: String?
            if let first, first.isTruthy {
                let own = best["city"]
                city = PlanJS.string(own.isTruthy ? own : first)
            }
            return (best, .string(city.map { "\(label) \u{00B7} \($0)" } ?? label))
        }

        func pickActivities(_ section: JSONValue) -> [Pick] {
            let priced = PlanJS.listOf(section).filter { activity in
                guard activity["name"].isTruthy, let price = PlanJS.num(activity["price_usd"]) else { return false }
                return price >= 0
            }
            var byCity: [String: [Double]] = [:]
            for activity in priced { byCity[PlanJS.cityKey(activity["city"]), default: []].append(PlanJS.num(activity["price_usd"]) ?? 0) }
            let cap = byCity.mapValues { max(activityPriceFloor, PlanJS.median($0)) }
            let cands = priced.filter { (PlanJS.num($0["price_usd"]) ?? 0) <= (cap[PlanJS.cityKey($0["city"])] ?? 0) }
            let sorted = PlanJS.sortBy(cands, [
                PlanJS.byDesc { PlanJS.num($0["similarity_score"]) }, PlanJS.byAsc { PlanJS.num($0["price_usd"]) },
            ])
            return takePerCity(sorted, perCity: maxActivitiesPerCity, total: maxActivities).map { activity in
                let price = PlanJS.num(activity["price_usd"]) ?? 0
                let base = price == 0 ? tt("plan:best.free", [:])
                    : price > activityPriceFloor ? tt("plan:best.reason.typicalPrice", ["price": money(price)]) : money(price)
                let matches = (PlanJS.num(activity["similarity_score"]) ?? -1) >= 0.5
                return (activity, .string(matches ? tt("plan:best.reason.matches", ["base": base]) : base))
            }
        }

        func pickWalkingTours(_ section: JSONValue) -> [Pick] {
            func topFirst(_ lhs: JSONValue, _ rhs: JSONValue) -> Double {
                (rhs["top_pick"].isTruthy ? 1 : 0) - (lhs["top_pick"].isTruthy ? 1 : 0)
            }
            let ordering: [(JSONValue, JSONValue) -> Double] = [topFirst, PlanJS.byDesc { PlanJS.num($0["rating"]) }]
            let sorted = PlanJS.sortBy(PlanJS.listOf(section).filter { $0["url"].isTruthy }, ordering)
            let perCity = takePerCity(sorted, perCity: 1, total: Int.max)
            return PlanJS.sortBy(perCity, ordering).prefix(maxWalkingTours).map { tour in
                (tour, tour["price_note"].isTruthy ? tour["price_note"] : text("best.reason.freeTour"))
            }
        }

        func pickPlaces(_ section: JSONValue) -> [Pick] {
            let free = PlanJS.listOf(section).filter { $0["name"].isTruthy && PlanJS.num($0["admission_fee_usd"]) == 0 }
            let sorted = PlanJS.sortBy(free, [PlanJS.byDesc { PlanJS.num($0["rating"]) }])
            return takePerCity(sorted, perCity: maxPlacesPerCity, total: maxPlaces).map { ($0, text("best.reason.freeEntry")) }
        }

        func pickSim(_ section: JSONValue, _ searchData: JSONValue) -> Pick? {
            let plans = section.isTruthy && !section["error"].isTruthy ? (section["plans"].array ?? []).filter(\.isTruthy) : []
            let priced = plans.filter { ($0["provider"].isTruthy || $0["plan_name"].isTruthy) && (PlanJS.num($0["price_usd"]) ?? 0) > 0 }
            if priced.isEmpty { return nil }
            func cheapest(_ arr: [JSONValue]) -> JSONValue { PlanJS.sortBy(arr, [PlanJS.byAsc { PlanJS.num($0["price_usd"]) }])[0] }
            if let days = tripDays(searchData) {
                let covering = priced.filter { plan in PlanJS.num(plan["validity_days"]).map { $0 >= days } ?? true }
                if !covering.isEmpty {
                    return (cheapest(covering), text("best.reason.coversTrip", ["days": PlanJS.numberString(days)]))
                }
            }
            return (cheapest(priced), text("best.reason.cheapestPlan"))
        }
    }

    private static func tripDays(_ searchData: JSONValue) -> Double? {
        guard searchData["departure_date"].isTruthy, searchData["return_date"].isTruthy else { return nil }
        let span = (PlanJS.ms(searchData["return_date"]) - PlanJS.ms(searchData["departure_date"])) / PlanJS.dayMs
        return span.isFinite ? PlanJS.round(span) + 1 : nil
    }
}
