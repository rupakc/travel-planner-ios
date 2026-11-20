import Foundation
import VoyagerModel

/// The place facts section (travel-planner `docs/Place-Facts.md`, web `PlaceFactsSection.jsx` +
/// `utils/placeFactText.js`): five groups of facts about each destination, its region and its country.
/// Crawler facts carry a citation (source name, link, as-of, licence attribution); AI facts are "AI-suggested,
/// not verified" and never carry a source. An older backend never sends the section, so everything here
/// tolerates missing or odd-typed fields.
public enum PlaceFacts {
    /// The five groups, in the web's tab order (`FACT_TYPES`).
    public static let factTypes = ["historical", "fun", "popular", "unbelievable", "little_known"]

    /// The selections field My Plan keeps facts in.
    public static let selectionField = "place_facts"

    /// Where a crawler fact comes from (`citation`).
    public struct Citation: Sendable, Equatable {
        public var name: String
        /// `http(s)` with a host only (the web's `safeUrl`); anything else is not linked.
        public var url: URL?
        /// `YYYY-MM-DD` (the first ten characters of `as_of`), when given.
        public var asOf: String?
        public var attribution: String?
        public var licenceURL: URL?
        public var conflict: Bool

        public init(name: String, url: URL?, asOf: String?, attribution: String?, licenceURL: URL?, conflict: Bool) {
            self.name = name
            self.url = url
            self.asOf = asOf
            self.attribution = attribution
            self.licenceURL = licenceURL
            self.conflict = conflict
        }
    }

    /// One fact, from the section or from a saved plan (`selections.place_facts`).
    public struct Fact: Sendable, Equatable, Identifiable {
        public var id: String
        public var factType: String?
        public var text: String
        /// `origin == "crawler"`; everything else is AI-suggested.
        public var isCrawler: Bool
        /// The language of the text as shown, when it is a valid tag (`und` is none).
        public var lang: String?
        /// The language of a quoted value in the text, raw (as the web keeps it in the plan).
        public var valueLang: String?
        public var machineTranslated: Bool
        /// Only for a crawler fact with a named source.
        public var citation: Citation?
        /// The item as the backend (or the saved plan) sent it.
        public var raw: JSONValue

        public var isAI: Bool { !isCrawler }
    }

    /// One place (`city`, `place`, `region` or `country`) and its non-empty groups.
    public struct Place: Sendable, Equatable, Identifiable {
        public var key: String
        public var name: String
        public var scope: String?
        /// Every fact type of `factTypes`, each with its facts (possibly none).
        public var groups: [String: [Fact]]

        public init(key: String, name: String, scope: String?, groups: [String: [Fact]]) {
            self.key = key
            self.name = name
            self.scope = scope
            self.groups = groups
        }

        public var id: String { key }

        /// The fact types with at least one fact, in tab order.
        public var availableTypes: [String] { PlaceFacts.factTypes.filter { !(groups[$0] ?? []).isEmpty } }
    }

    // MARK: - Section

    /// The places that have at least one fact (`placesWithFacts`): an error, a missing `places` list or a place
    /// without groups gives nothing; a fact needs non-blank text.
    public static func places(_ data: JSONValue?) -> [Place] {
        guard let data, data.object != nil, !data["error"].isTruthy, let list = data["places"].array else { return [] }
        return list.enumerated().compactMap { offset, value -> Place? in
            guard value.object != nil, value["groups"].object != nil else { return nil }
            let key = nonBlank(value["key"]) ?? "place-\(offset)"
            var groups: [String: [Fact]] = [:]
            for type in factTypes {
                groups[type] = (value["groups"][type].array ?? []).compactMap { fact($0, placeKey: key) }
            }
            let place = Place(key: key, name: nonBlank(value["name"]) ?? "", scope: nonBlank(value["scope"]), groups: groups)
            return place.availableTypes.isEmpty ? nil : place
        }
    }

    /// Whether the section has anything to show (`hasPlaceFacts`).
    public static func hasFacts(_ data: JSONValue?) -> Bool {
        !places(data).isEmpty
    }

    /// One fact item, or nil when it has no text.
    public static func fact(_ value: JSONValue, placeKey: String? = nil) -> Fact? {
        guard value.object != nil, let text = value["text"].string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let crawler = value["origin"].string == "crawler"
        let id = nonBlank(value["id"]) ?? "\(placeKey ?? ""):\(text)"
        return Fact(
            id: id, factType: value["fact_type"].string, text: text, isCrawler: crawler, lang: langAttr(value["lang"].string),
            valueLang: value["value_lang"].string, machineTranslated: value["machine_translated"].bool == true,
            citation: crawler ? citation(value["citation"]) : nil, raw: value)
    }

    /// A citation with a name (`name`, else `source_id`); anything else is nil.
    static func citation(_ value: JSONValue) -> Citation? {
        guard value.object != nil, let name = nonBlank(value["name"]) ?? nonBlank(value["source_id"]) else { return nil }
        let asOf = value["as_of"].string.flatMap { raw -> String? in
            raw.prefixMatch(of: /\d{4}-\d{2}-\d{2}/).map { String($0.output) }
        }
        return Citation(
            name: name, url: webURL(value["url"]), asOf: asOf, attribution: nonBlank(value["attribution"]),
            licenceURL: webURL(value["licence_url"]), conflict: value["conflict"].bool == true)
    }

    // MARK: - My Plan

    /// What My Plan keeps for one fact (`factSelection`): `{id, text, fact_type, place, origin, lang, value_lang,
    /// citation}`, where `citation` is null for AI facts. The same shape the web saves (plus the citation's
    /// `conflict` flag, which the web ignores), so plans round-trip.
    public static func selection(_ fact: Fact, placeName: String?) -> JSONValue {
        let raw = fact.raw
        var citation: JSONValue = .null
        if fact.isCrawler, raw["citation"].isTruthy {
            let source = raw["citation"]
            func field(_ key: String) -> JSONValue { nonBlank(source[key]).map(JSONValue.string) ?? .null }
            citation = .object([
                // The card's name falls back to `source_id`; keep that name so the plan still shows the source.
                "name": nonBlank(source["name"]).map(JSONValue.string) ?? field("source_id"), "url": field("url"),
                "as_of": field("as_of"), "attribution": field("attribution"), "licence_url": field("licence_url"),
                "conflict": .bool(source["conflict"].bool == true),
            ])
        }
        return .object([
            "id": .string(fact.id),
            "text": .string(fact.text),
            "fact_type": fact.factType.map(JSONValue.string) ?? .null,
            "place": placeName.flatMap { $0.isEmpty ? nil : JSONValue.string($0) } ?? .null,
            "origin": .string(fact.isCrawler ? "crawler" : "ai"),
            "lang": fact.lang.map(JSONValue.string) ?? .null,
            "value_lang": fact.valueLang.map(JSONValue.string) ?? .null,
            "citation": citation,
        ])
    }

    /// A fact kept in My Plan, read back (a plan saved on the web reads the same; an old `quote` flag is ignored,
    /// so that fact shows as plain text with its attribution).
    public static func selected(_ value: JSONValue) -> (fact: Fact, place: String?)? {
        guard let fact = fact(value) else { return nil }
        return (fact, nonBlank(value["place"]))
    }

    // MARK: - Language tags (`placeFactText.js`)

    /// A BCP 47 tag worth marking, else nil (`und`, junk and over-long values too).
    public static func langAttr(_ tag: String?) -> String? {
        guard let tag, tag.count <= 35, tag.wholeMatch(of: /[A-Za-z]{2,3}(?:-[A-Za-z0-9]{1,8})*/) != nil else { return nil }
        return tag.lowercased() == "und" ? nil : tag
    }

    /// The text split around its one quoted value (“…”) when the fact names the value's language.
    public struct QuotedValue: Sendable, Equatable {
        /// Up to and including the opening quote.
        public var before: String
        public var value: String
        /// From the closing quote on.
        public var after: String
        public var lang: String
    }

    /// `quotedValue`: nil when there is no valid value language, no quote pair, more than one, or an empty value.
    public static func quotedValue(_ text: String, valueLang: String?) -> QuotedValue? {
        guard let lang = langAttr(valueLang), let open = text.firstIndex(of: "“") else { return nil }
        let rest = text.index(after: open)
        guard let close = text[rest...].firstIndex(of: "”") else { return nil }
        if text[close...].contains("“") { return nil }
        let value = String(text[rest..<close])
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return QuotedValue(before: String(text[...open]), value: value, after: String(text[close...]), lang: lang)
    }

    /// The fact's text tagged with its languages (the web's `<span lang>`): the whole text in `lang` when known,
    /// the quoted value in `value_lang`. VoiceOver and line breaking follow the tags.
    public static func attributedText(_ fact: Fact) -> AttributedString {
        var out: AttributedString
        if let parts = quotedValue(fact.text, valueLang: fact.valueLang) {
            out = AttributedString(parts.before)
            var value = AttributedString(parts.value)
            value.languageIdentifier = parts.lang
            out += value
            out += AttributedString(parts.after)
        } else {
            out = AttributedString(fact.text)
        }
        if let lang = fact.lang {
            for run in out.runs where run.languageIdentifier == nil {
                out[run.range].languageIdentifier = lang
            }
        }
        return out
    }

    // MARK: - Reading

    private static func nonBlank(_ value: JSONValue) -> String? {
        guard let text = value.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// `http://` or `https://` with a host, as the web's `safeUrl` and the backend's `_URL_RE` accept.
    private static func webURL(_ value: JSONValue) -> URL? {
        guard let raw = value.string?.trimmingCharacters(in: .whitespacesAndNewlines),
            raw.lowercased().hasPrefix("https://") || raw.lowercased().hasPrefix("http://"),
            let url = URL(string: raw), !(url.host() ?? "").isEmpty
        else { return nil }
        return url
    }
}
