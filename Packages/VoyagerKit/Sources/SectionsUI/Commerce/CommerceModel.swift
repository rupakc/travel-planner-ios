import Foundation
import L10n
import VoyagerModel

/// One group of flights: the whole result (single trip) or one leg of a multi-city trip.
struct FlightLegGroup: Identifiable, Equatable {
    /// The 0-based `leg_index`; `0` for a single trip.
    let id: Int
    /// The backend's leg label (`"Paris → Rome"`), for a multi-city trip.
    let label: String?
    let flights: [JSONValue]
    let error: String?
}

enum HotelTier: Int, CaseIterable, Sendable {
    case luxury, premium, midRange, budget, other
}

/// The pure rules behind the commerce sections (flights, hotels, activities, SIM).
enum Commerce {
    /// A count or measure in the app language: whole numbers without decimals, else one decimal.
    static func compact(_ value: Double) -> String {
        Fmt.number(value, fractionDigits: value.rounded() == value ? 0 : 1)
    }

    // MARK: Flights

    static func isMultiCity(_ data: JSONValue) -> Bool {
        data["trip_type"].string == "multi_city" && !(data["legs"].array ?? []).isEmpty
    }

    /// Single trip: one group of `results`. Multi-city: one group per leg, each flight carrying its `leg_index`
    /// (the plan keeps one fare per leg).
    static func flightGroups(_ data: JSONValue) -> [FlightLegGroup] {
        guard isMultiCity(data), let legs = data["legs"].array else {
            return [FlightLegGroup(id: 0, label: nil, flights: data["results"].array ?? [], error: nil)]
        }
        return legs.enumerated().map { position, leg in
            let index = leg["leg_index"].double.map { Int($0) } ?? position
            let flights = (leg["results"].array ?? []).map { flight -> JSONValue in
                guard flight["leg_index"].double == nil, case .object(var object) = flight else { return flight }
                object["leg_index"] = .number(Double(index))
                return .object(object)
            }
            return FlightLegGroup(id: index, label: leg["label"].string, flights: flights, error: leg["error"].string)
        }
    }

    /// Legs of a multi-city trip that have a chosen fare, and the total number of legs.
    static func legProgress(_ data: JSONValue, isSelected: (JSONValue) -> Bool) -> (chosen: Int, total: Int) {
        let groups = flightGroups(data)
        return (groups.filter { $0.flights.contains(where: isSelected) }.count, groups.count)
    }

    /// The cheapest priced, live fare of a single-city result: the fare watch's "today" price.
    static func cheapestLivePrice(_ data: JSONValue) -> Double? {
        guard !isMultiCity(data) else { return nil }
        return (data["results"].array ?? []).map(SectionItem.init)
            .filter { !$0.isEstimate }.compactMap(\.priceUSD).filter { $0 > 0 }.min()
    }

    /// `price_insights.price_level` when it is one of low / typical / high.
    static func insightLevel(_ insights: JSONValue) -> String? {
        guard let level = insights["price_level"].string, ["low", "typical", "high"].contains(level) else { return nil }
        return level
    }

    /// `price_insights.typical_price_range` as `(low, high)` when both are finite numbers.
    static func typicalRange(_ insights: JSONValue) -> (low: Double, high: Double)? {
        guard let range = insights["typical_price_range"].array, range.count == 2,
            let low = range[0].double, let high = range[1].double, low.isFinite, high.isFinite
        else { return nil }
        return (low, high)
    }

    /// Minutes as `(hours, minutes)`; nil for a missing or non-positive duration.
    static func hoursMinutes(_ minutes: Double?) -> (Int, Int)? {
        guard let minutes, minutes.isFinite, minutes > 0 else { return nil }
        let total = Int(minutes.rounded())
        return (total / 60, total % 60)
    }

    // MARK: Hotels

    static func tier(of hotel: JSONValue) -> HotelTier {
        guard let stars = hotel["star_rating"].double, stars.isFinite, stars > 0 else { return .other }
        switch Int(stars.rounded()) {
        case 5...: return .luxury
        case 4: return .premium
        case 3: return .midRange
        default: return .budget
        }
    }

    /// Hotels grouped by budget tier (luxury first), keeping the backend's order inside a tier. Empty tiers are dropped.
    static func hotelTiers(_ hotels: [JSONValue]) -> [(tier: HotelTier, hotels: [JSONValue])] {
        HotelTier.allCases.compactMap { tier in
            let members = hotels.filter { Self.tier(of: $0) == tier }
            return members.isEmpty ? nil : (tier, members)
        }
    }

    // MARK: Activities

    /// Activities from the user's link first (`from_link`), then the rest; each part keeps its order.
    static func activitiesFromLinkFirst(_ items: [JSONValue]) -> [JSONValue] {
        items.filter { $0["from_link"].isTruthy } + items.filter { !$0["from_link"].isTruthy }
    }

    // MARK: SIM

    /// `data_gb` arrives as a number or a string (`"10"`, `"Unlimited"`).
    static func simData(_ plan: JSONValue) -> (gb: String?, unlimited: Bool) {
        if case .number(let number) = plan["data_gb"], number.isFinite {
            return (number.rounded() == number ? String(Int(number)) : String(number), false)
        }
        guard let text = plan["data_gb"].string?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return (nil, false) }
        if text.lowercased().contains("unlimited") { return (nil, true) }
        return (text.lowercased().hasSuffix("gb") ? String(text.dropLast(2)).trimmingCharacters(in: .whitespaces) : text, false)
    }
}

/// How a remote call made by a section ended. The host maps its own errors onto this (SectionsUI never sees
/// the networking layer).
public enum SectionRemote: Sendable, Equatable {
    case loaded(JSONValue)
    /// `503`: the server cannot do this (no `SERPAPI_KEY`, no grounding). The control is hidden, not an error.
    case unavailable
    /// Any other failure; the server's own text when it sent one.
    case failed(String?)
}
