import Foundation
import VoyagerModel

/// The specs a "Watch" tap hands to the watch coordinator: ports of `tripFromSearch`, `hotelWatchSpec` and
/// `activitySpec` of the web, for single-destination trips. Each returns nil when the card cannot be watched
/// (no dates, a past departure, a multi-city trip, an estimate).
enum WatchSpecs {
    /// `YYYY-MM-DD` of `date` in UTC.
    static func iso(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    private static func isMultiCity(_ search: JSONValue) -> Bool {
        (search["destinations"].array?.count ?? 0) > 1
    }

    private static func nights(from start: String, to end: String) -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let first = formatter.date(from: start), let last = formatter.date(from: end) else { return 0 }
        return Int((last.timeIntervalSince(first) / 86_400).rounded())
    }

    /// `{origin, destination, departure_date, return_date, num_travelers}` for a fare watch.
    static func fare(search: JSONValue?, now: Date = Date()) -> JSONValue? {
        guard let search, !isMultiCity(search),
            let origin = search["origin"].string, !origin.isEmpty,
            let destination = search["destination"].string, !destination.isEmpty,
            let departure = search["departure_date"].string, departure > iso(now)
        else { return nil }
        return [
            "origin": .string(origin), "destination": .string(destination), "departure_date": .string(departure),
            "return_date": search["return_date"].string.map(JSONValue.string) ?? .null,
            "num_travelers": .number(Double(max(1, search["num_travelers"].int ?? 1))),
        ]
    }

    /// Adults as Google Hotels guests (every traveller counts) and one room per four guests.
    static func guests(_ search: JSONValue) -> (adults: Int, rooms: Int) {
        let counted = ["adults", "seniors", "children"].reduce(0) { $0 + max(0, search[$1].int ?? 0) }
        let guests = min(16, max(1, counted > 0 ? counted : (search["num_travelers"].int ?? 1)))
        return (guests, guests <= 4 ? 1 : (guests + 3) / 4)
    }

    /// `{name, city, check_in, check_out, adults, rooms, estimate_total?}`.
    static func hotel(_ hotel: JSONValue, search: JSONValue?, now: Date = Date()) -> JSONValue? {
        guard let search, !isMultiCity(search),
            let name = hotel["name"].string?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
            let checkIn = search["departure_date"].string, let checkOut = search["return_date"].string,
            checkIn > iso(now)
        else { return nil }
        let stay = nights(from: checkIn, to: checkOut)
        let city = hotel["city"].string ?? search["destination"].string ?? ""
        guard stay >= 1, !city.isEmpty else { return nil }
        let party = guests(search)
        var spec: [String: JSONValue] = [
            "name": .string(name), "city": .string(city), "check_in": .string(checkIn), "check_out": .string(checkOut),
            "adults": .number(Double(party.adults)), "rooms": .number(Double(party.rooms)),
        ]
        let perRoom = hotel["total_price_usd"].double.flatMap { $0 > 0 ? $0 : nil }
            ?? hotel["price_per_night_usd"].double.flatMap { $0 > 0 ? ($0 * Double(stay)).rounded() : nil }
        if let perRoom { spec["estimate_total"] = .number(perRoom * Double(party.rooms)) }
        return .object(spec)
    }

    /// `{name, city, travellers, estimate_price?}`.
    static func activity(_ activity: JSONValue, search: JSONValue?) -> JSONValue? {
        guard let search, !isMultiCity(search),
            let name = activity["name"].string?.trimmingCharacters(in: .whitespaces), !name.isEmpty
        else { return nil }
        let destination = (search["destination"].string ?? "").split(separator: ",").first.map(String.init) ?? ""
        let city = (activity["city"].string ?? destination).trimmingCharacters(in: .whitespaces)
        guard !city.isEmpty else { return nil }
        let party = search["num_travelers"].int.flatMap { $0 >= 1 ? $0 : nil }
            ?? max(1, ["adults", "children", "seniors"].reduce(0) { $0 + max(0, search[$1].int ?? 0) })
        var spec: [String: JSONValue] = ["name": .string(name), "city": .string(city), "travellers": .number(Double(min(party, 20)))]
        if let price = activity["price_usd"].double, price.isFinite, price > 0 { spec["estimate_price"] = .number(price) }
        return .object(spec)
    }
}
