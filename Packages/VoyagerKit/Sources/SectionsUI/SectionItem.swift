import Foundation
import VoyagerModel

/// Read-only typed accessors over one backend item (a flight, hotel, activity, SIM plan, ...).
/// Backend items are LLM output, so every accessor tolerates a missing or odd-typed field.
public struct SectionItem: Sendable, Equatable {
    public let value: JSONValue

    public init(_ value: JSONValue) {
        self.value = value
    }

    /// The display name: `name`, else `title`, `plan_name` or `provider`.
    public var name: String? {
        for key in ["name", "title", "plan_name", "provider"] {
            if let text = value[key].string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// `price_usd` when it is a finite, non-negative number.
    public var priceUSD: Double? {
        guard let price = value["price_usd"].double, price.isFinite, price >= 0 else { return nil }
        return price
    }

    /// The provider page: `booking_url` (else `url`), `https` with a host only; anything else is nil.
    public var bookingURL: URL? {
        for key in ["booking_url", "url"] {
            if let raw = value[key].string, let url = Self.httpsURL(raw) { return url }
        }
        return nil
    }

    /// `rating` when it is a number in 0...5 (a 0-10 scale or junk is not shown).
    public var rating: Double? {
        guard let rating = value["rating"].double, rating.isFinite, (0...5).contains(rating) else { return nil }
        return rating
    }

    /// Estimates are always labelled: `source == "estimate"`, or a flight fare that is not live (`live_fare == false`).
    public var isEstimate: Bool {
        value["source"].string == "estimate" || value["live_fare"].bool == false
    }

    static func httpsURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme?.lowercased() == "https", !(url.host()?.isEmpty ?? true)
        else { return nil }
        return url
    }
}
