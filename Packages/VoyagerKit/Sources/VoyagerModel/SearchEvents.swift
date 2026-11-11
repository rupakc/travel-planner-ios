import Foundation

/// Whether a section's data is the instant static table or the AI result.
public enum SectionSource: String, Codable, Sendable, Hashable {
    case `static`
    case ai
}

/// One `/api/search` SSE `data:` object (`type` selects the case). Section payloads stay
/// `JSONValue`; the `Domain` layer reads them.
public enum SearchStreamEvent: Sendable, Equatable {
    case section(type: String, source: SectionSource?, data: JSONValue)
    case agentStatus(agent: String, status: String)
    case done
    case unknown(String)

    /// Section event types `/api/search` streams (docs/API-Reference.md, "Event" table).
    public static let sectionTypes: Set<String> = [
        "visa", "sim", "tips", "getting_around", "forex", "confidence", "emergency_card",
        "flights", "weather", "hotels", "activities", "places_to_see", "walking_tours", "events",
        "packing_list", "pricing_advisor", "itinerary", "stress_test",
    ]

    public init(json: JSONValue) {
        let type = json["type"].string ?? ""
        switch type {
        case "done":
            self = .done
        case "agent_status":
            self = .agentStatus(agent: json["agent"].string ?? "", status: json["status"].string ?? "")
        case _ where Self.sectionTypes.contains(type):
            self = .section(type: type, source: json["source"].string.flatMap(SectionSource.init(rawValue:)), data: json["data"])
        default:
            self = .unknown(type)
        }
    }
}

/// One `/api/chat` SSE `data:` object.
public enum ChatStreamEvent: Sendable, Equatable {
    case delta(String)
    case suggestions([String])
    case sessionContextUpdate(JSONValue)
    case planAction(action: String, field: String, data: JSONValue)
    case planningStart(destination: String?)
    /// The whole `trip_map` event object (origin, cities, dates, travellers).
    case tripMap(JSONValue)
    case itineraryGenerating
    case comprehensiveItinerary(JSONValue)
    case agentStatus(agent: String, status: String)
    case sectionResult(section: String, source: SectionSource?, data: JSONValue)
    case importLink(url: String)
    case planningDone
    case error(String)
    case done
    case unknown(String)

    public init(json: JSONValue) {
        let type = json["type"].string ?? ""
        switch type {
        case "delta":
            self = .delta(json["text"].string ?? "")
        case "suggestions":
            self = .suggestions((json["chips"].array ?? []).compactMap(\.string))
        case "session_context_update":
            self = .sessionContextUpdate(json["context"])
        case "plan_action":
            self = .planAction(action: json["action"].string ?? "", field: json["field"].string ?? "", data: json["data"])
        case "planning_start":
            self = .planningStart(destination: json["destination"].string)
        case "trip_map":
            self = .tripMap(json)
        case "itinerary_generating":
            self = .itineraryGenerating
        case "comprehensive_itinerary":
            self = .comprehensiveItinerary(json["data"])
        case "agent_status":
            self = .agentStatus(agent: json["agent"].string ?? "", status: json["status"].string ?? "")
        case "section_result":
            self = .sectionResult(
                section: json["section"].string ?? "",
                source: json["source"].string.flatMap(SectionSource.init(rawValue:)),
                data: json["data"]
            )
        case "import_link":
            self = .importLink(url: json["url"].string ?? "")
        case "planning_done":
            self = .planningDone
        case "error":
            self = .error(json["text"].string ?? json["message"].string ?? "")
        case "done":
            self = .done
        default:
            self = .unknown(type)
        }
    }
}
