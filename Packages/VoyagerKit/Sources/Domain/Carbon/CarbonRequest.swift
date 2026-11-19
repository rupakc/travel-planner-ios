import Foundation
import VoyagerModel

/// The request body of `POST /api/carbon/trip` (travel-planner `docs/Carbon-Footprint.md`); a port of
/// `frontend/src/utils/carbon.js`, golden-tested against the web. The backend does all the arithmetic: this only
/// trims what the screen holds down to the fields the calculator reads, so the body stays small (the endpoint caps it
/// at 512 KB) and a new field on a result never changes it.
public enum CarbonRequest {
    public static let diets = ["mixed", "meat_heavy", "pescatarian", "vegetarian", "vegan"]
    public static let categoryKeys = ["flights", "stays", "ground", "food", "activities"]

    private static let searchFields = [
        "origin", "destination", "destinations", "destination_nights",
        "departure_date", "return_date", "num_travelers", "adults", "children", "seniors",
    ]
    private static let legFields = ["origin", "destination", "stops", "emissions", "leg_index", "flight_number", "departure_date"]

    /// Body for a whole search result (the Results card): the cheapest flight (per leg on a multi-city trip), the
    /// first hotel and the itinerary's stops.
    public static func fromResults(searchData: JSONValue?, results: JSONValue, diet: String) -> JSONValue {
        let flightsSection = results["flights"]
        var flights: [String: JSONValue] = [:]
        if let legs = flightsSection["legs"].array, !legs.isEmpty {
            flights["legs"] = .array(legs.map { .object(["results": .array(cheapestTrimmed($0["results"]))]) })
        } else if let list = flightsSection["results"].array {
            flights["results"] = .array(cheapestTrimmed(.array(list)))
        }
        let hotel = trimHotel(results["hotels"]["results"][0])
        var body: [String: JSONValue] = [
            "search": pick(searchData ?? .null, searchFields),
            "results": .object([
                "flights": .object(flights),
                "hotels": .object(["results": .array(hotel.isNull ? [] : [hotel])]),
            ]),
            "diet": .string(normalDiet(diet)),
        ]
        let itinerary = trimItinerary(results["itinerary"])
        if !itinerary.isNull { body["itinerary"] = itinerary }
        return .object(body)
    }

    /// Body for a plan's selections (the My Plan card).
    public static func fromSelections(searchData: JSONValue?, selections: JSONValue, itinerary: JSONValue?, diet: String) -> JSONValue {
        let picked = selections
        var body: [String: JSONValue] = [
            "search": pick(searchData ?? .null, searchFields),
            "selections": .object([
                "flight": trimFlight(picked["flight"]),
                "flights": .array((picked["flights"].array ?? []).map(trimFlight).filter(\.isTruthy)),
                "hotel": trimHotel(picked["hotel"]),
                "getting_around": .array((picked["getting_around"].array ?? []).map { pick($0, ["type", "scope"]) }),
                "activities": .array((picked["activities"].array ?? []).map { pick($0, ["name"]) }),
            ]),
            "diet": .string(normalDiet(diet)),
        ]
        let trimmed = trimItinerary(itinerary ?? .null)
        if !trimmed.isNull { body["itinerary"] = trimmed }
        return .object(body)
    }

    /// True when a selection has anything the footprint counts beyond meals (the plan card shows only then).
    public static func selectionsHaveTravel(_ selections: JSONValue) -> Bool {
        selections["flight"].isTruthy || !(selections["flights"].array ?? []).isEmpty || selections["hotel"].isTruthy
    }

    /// A share (0-1) as a whole percent, "<1%" for small non-zero shares.
    public static func pctLabel(_ share: Double?) -> String {
        guard let share, share > 0 else { return "0%" }
        if share < 0.005 { return "<1%" }
        return "\(Int((share * 100 + 0.5).rounded(.down)))%"
    }

    /// The lowest-priced result (the first among equals; a missing or 0 price, which SerpAPI gives when it has none,
    /// sorts last). `.null` for an empty or missing list.
    public static func cheapest(_ list: JSONValue) -> JSONValue {
        let candidates = (list.array ?? []).filter { $0.object != nil }
        var best: JSONValue?
        for candidate in candidates where best == nil || price(candidate) < price(best ?? .null) {
            best = candidate
        }
        return best ?? .null
    }

    /// A flight trimmed to the fields the calculator reads (`.null` for anything that is not an object).
    public static func trimFlight(_ flight: JSONValue) -> JSONValue {
        guard flight.object != nil else { return .null }
        var out = trimLeg(flight)
        for key in ["outbound", "return"] where flight[key].isTruthy {
            let leg = flight[key]
            if leg.object != nil { out[key] = .object(trimLeg(leg)) }
        }
        return .object(out)
    }

    /// The itinerary's days (at most 60) and slots (at most 12 a day), each slot only `activity`, `lat`, `lng`.
    public static func trimItinerary(_ itinerary: JSONValue) -> JSONValue {
        guard let days = itinerary["days"].array, !days.isEmpty else { return .null }
        return .object([
            "days": .array(days.prefix(60).map { day in
                .object(["slots": .array((day["slots"].array ?? []).prefix(12).map { pick($0, ["activity", "lat", "lng"]) })])
            }),
        ])
    }

    // MARK: - Helpers

    private static func normalDiet(_ diet: String) -> String { diets.contains(diet) ? diet : "mixed" }

    private static func cheapestTrimmed(_ list: JSONValue) -> [JSONValue] {
        let trimmed = trimFlight(cheapest(list))
        return trimmed.isNull ? [] : [trimmed]
    }

    private static func trimLeg(_ leg: JSONValue) -> [String: JSONValue] {
        var out = pick(leg, legFields).object ?? [:]
        if let layovers = leg["layovers"].array { out["layovers"] = .array(layovers.map { pick($0, ["airport"]) }) }
        if let segments = leg["segments"].array {
            out["segments"] = .array(segments.map { pick($0, ["flight_number", "origin", "destination", "departure_date"]) })
        }
        return out
    }

    private static func trimHotel(_ hotel: JSONValue) -> JSONValue {
        hotel.object != nil ? pick(hotel, ["name", "city", "country_code"]) : .null
    }

    /// The listed keys that are present and not null (an object even when `value` is not one).
    static func pick(_ value: JSONValue, _ keys: [String]) -> JSONValue {
        var out: [String: JSONValue] = [:]
        for key in keys where !value[key].isNull { out[key] = value[key] }
        return .object(out)
    }

    /// `Number(r.price_usd ?? r.price)` when that is a finite positive number, else infinity (sorts last).
    private static func price(_ result: JSONValue) -> Double {
        let raw = result["price_usd"].isNull ? result["price"] : result["price_usd"]
        let value: Double?
        switch raw {
        case .number(let number): value = number
        case .string: value = raw.double
        case .bool(let flag): value = flag ? 1 : 0
        default: value = nil
        }
        guard let value, value.isFinite, value > 0 else { return .infinity }
        return value
    }
}
