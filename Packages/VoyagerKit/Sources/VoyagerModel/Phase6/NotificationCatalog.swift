import Foundation

/// `GET /api/notifications/catalog?locale=xx`: `{"locale": "es", "templates": {"nearby_arrival": "...{place}..."}}`.
/// Template keys this app does not know are kept but never used; a non-string value is dropped.
public struct NotificationCatalog: Codable, Sendable, Hashable {
    public var locale: String
    public var templates: [String: String]

    public init(locale: String = "en", templates: [String: String] = [:]) {
        self.locale = locale
        self.templates = templates
    }

    enum CodingKeys: String, CodingKey { case locale, templates }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard json.object != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Catalog is an object"))
        }
        locale = json["locale"].string ?? "en"
        var found: [String: String] = [:]
        for (key, value) in json["templates"].object ?? [:] {
            if let text = value.string, !text.isEmpty { found[key] = text }
        }
        templates = found
    }

    public func template(_ key: String) -> String? { templates[key] }

    /// The template with every `{name}` filled from `values`; nil when the template is missing or a placeholder has no
    /// value (callers then use their own copy, so no half-filled text is ever shown).
    public func render(_ key: String, _ values: [String: String]) -> String? {
        guard let template = templates[key] else { return nil }
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            result += rest[rest.startIndex..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { return nil }
            let name = String(rest[rest.index(after: open)..<close])
            guard let value = values[name] else { return nil }
            result += value
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    /// Used when there is neither a network answer nor a cached one: the English templates the app can show alone.
    public static let bundledEnglish = NotificationCatalog(
        locale: "en",
        templates: [
            "trip_t30": "{destination} is {days} days away. Check your visa and entry rules.",
            "trip_t7": "{days} days to {destination}. Time to pack.",
            "trip_t1": "Tomorrow you fly to {destination}. Check in and review the weather.",
            "trip_morning": "Good morning from {destination}. Open Today for your plan.",
            "nearby_arrival": "You're near {place}: {item} is {minutes} min away",
        ])
}

/// The template keys of the contract that this app uses.
public enum NotificationTemplateKey {
    public static let tripT30 = "trip_t30"
    public static let tripT7 = "trip_t7"
    public static let tripT1 = "trip_t1"
    public static let tripMorning = "trip_morning"
    public static let nearbyArrival = "nearby_arrival"
}
