import Foundation
import L10n
import SectionsUI
import VoyagerModel

enum ChatRole: String, Sendable, Equatable {
    case user, assistant
}

/// One specialist result shown inside an assistant message (`section_result`).
struct ChatSection: Equatable, Sendable {
    var id: String
    var data: JSONValue
    var source: SectionSource?
    /// Only an error ever arrived for this section (no earlier good data to keep).
    var failed: Bool
}

/// The planning stream of one assistant message: trip map, itinerary spinner, the `comprehensive_itinerary`.
struct PlanningState: Equatable, Sendable {
    var destination: String?
    var tripMap: JSONValue?
    var generating = false
    var itinerary: JSONValue?
    var itineraryError: String?
    var done = false
}

/// One chat message as the screen shows it (and as it is stored in a `ChatThread`, via `json`).
struct ChatMessageState: Equatable, Identifiable, Sendable {
    var id: String
    var role: ChatRole
    var content: String
    var suggestions: [String]
    var sections: [ChatSection]
    /// Specialists that reported `loading` and have not delivered yet (fallback path only).
    var loadingAgents: [String]
    var planning: PlanningState?
    var importURL: String?
    var failed: Bool

    init(
        id: String = UUID().uuidString, role: ChatRole, content: String = "", suggestions: [String] = [],
        sections: [ChatSection] = [], loadingAgents: [String] = [], planning: PlanningState? = nil,
        importURL: String? = nil, failed: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.suggestions = suggestions
        self.sections = sections
        self.loadingAgents = loadingAgents
        self.planning = planning
        self.importURL = importURL
        self.failed = failed
    }

    /// Nothing the user could read or act on.
    var isBlank: Bool {
        content.isEmpty && sections.isEmpty && planning == nil && importURL == nil
    }
}

/// What a stream event asks the host to do besides changing the message.
enum ChatEffect: Equatable, Sendable {
    case planAction(action: String, field: String, data: JSONValue)
    case openImport(String)
    /// The first `planning_start` of the turn.
    case planningStarted
    case tripMapped(JSONValue)
    /// A good section result: kept in `CurrentPlanStore.latestResults`.
    case sectionData(section: String, data: JSONValue)
}

/// The assistant turn being built from a stream.
struct ChatTurn: Equatable, Sendable {
    var message: ChatMessageState
    /// Set by `session_context_update`: replaces the context sent with the next request.
    var sessionContext: JSONValue?
    var finished = false

    init(message: ChatMessageState = ChatMessageState(role: .assistant)) {
        self.message = message
    }
}

/// Applies `ChatStreamEvent`s (api-contract §4.2). Pure: effects are returned, never performed.
enum ChatReducer {
    static let maxChips = 4

    static func reduce(_ turn: inout ChatTurn, _ event: ChatStreamEvent) -> [ChatEffect] {
        switch event {
        case .delta(let text):
            turn.message.content += text
        case .suggestions(let chips):
            turn.message.suggestions = Array(chips.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(maxChips))
        case .sessionContextUpdate(let context):
            if context.object != nil { turn.sessionContext = context }
        case .planAction(let action, let field, let data):
            return [.planAction(action: action, field: field, data: data)]
        case .planningStart(let destination):
            return startPlanning(&turn, destination: destination)
        case .tripMap, .itineraryGenerating, .comprehensiveItinerary:
            return reducePlanning(&turn, event)
        case .agentStatus(let agent, let status):
            if status == "loading", !turn.message.loadingAgents.contains(agent) { turn.message.loadingAgents.append(agent) }
        case .sectionResult(let section, let source, let data):
            return applySection(&turn, section: section, source: source, data: data)
        case .importLink(let url):
            turn.message.importURL = url
            return [.openImport(url)]
        case .planningDone:
            turn.finished = true
            stopPlanning(&turn)
        case .done:
            turn.finished = true
            stopPlanning(&turn)
        case .error:
            turn.message.failed = true
            stopPlanning(&turn)
            if turn.message.content.isEmpty { turn.message.content = L10n.text(K.chat.error.generic) }
        case .unknown:
            break
        }
        return []
    }

    private static func reducePlanning(_ turn: inout ChatTurn, _ event: ChatStreamEvent) -> [ChatEffect] {
        var planning = turn.message.planning ?? PlanningState()
        var effects: [ChatEffect] = []
        switch event {
        case .tripMap(let map):
            planning.tripMap = map
            effects = [.tripMapped(map)]
        case .itineraryGenerating:
            planning.generating = true
        case .comprehensiveItinerary(let data):
            planning.generating = false
            if let error = data["error"].string {
                planning.itineraryError = error
            } else {
                planning.itinerary = data
                planning.itineraryError = nil
            }
        default:
            break
        }
        turn.message.planning = planning
        return effects
    }

    /// The stream ended (cleanly or not): closes the turn, and says so when nothing at all came back.
    static func finish(_ turn: inout ChatTurn) {
        turn.finished = true
        stopPlanning(&turn)
        turn.message.loadingAgents = []
        if turn.message.isBlank {
            turn.message.content = L10n.text(K.chat.error.noResponse)
            turn.message.failed = true
        }
    }

    private static func startPlanning(_ turn: inout ChatTurn, destination: String?) -> [ChatEffect] {
        let first = turn.message.planning == nil
        var planning = turn.message.planning ?? PlanningState()
        if let destination, !destination.isEmpty { planning.destination = destination }
        turn.message.planning = planning
        return first ? [.planningStarted] : []
    }

    private static func stopPlanning(_ turn: inout ChatTurn) {
        guard var planning = turn.message.planning else { return }
        planning.generating = false
        planning.done = true
        turn.message.planning = planning
    }

    private static func applySection(
        _ turn: inout ChatTurn, section: String, source: SectionSource?, data: JSONValue
    ) -> [ChatEffect] {
        turn.message.loadingAgents.removeAll { $0 == section }
        guard SectionID(rawValue: section) != nil else { return [] }
        let isError = data["error"].string != nil
        let index = turn.message.sections.firstIndex { $0.id == section }
        if isError {
            // Keep prior good data; an error alone is shown as the section's unavailable state.
            if index == nil { turn.message.sections.append(ChatSection(id: section, data: data, source: source, failed: true)) }
            return []
        }
        let entry = ChatSection(id: section, data: data, source: source, failed: false)
        if let index { turn.message.sections[index] = entry } else { turn.message.sections.append(entry) }
        return [.sectionData(section: section, data: data)]
    }
}

// MARK: - Request history

enum ChatHistory {
    /// The messages sent to the server: the whole history, planning-only and section-only turns turned into
    /// text, and never an empty `content`.
    static func requestMessages(_ messages: [ChatMessageState]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        for message in messages {
            let text = text(for: message)
            guard !text.isEmpty else { continue }
            // A conversation starts with the user.
            if result.isEmpty, message.role == .assistant { continue }
            result.append(ChatMessage(role: message.role.rawValue, content: text))
        }
        return result
    }

    static func text(for message: ChatMessageState) -> String {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty { return content }
        guard message.role == .assistant else { return "" }
        if let planning = message.planning, planning.itinerary != nil || planning.tripMap != nil {
            let days = planning.itinerary?["days"].array?.count ?? 0
            let place = planning.destination ?? ""
            let dayText = days > 0 ? " (\(days) days)" : ""
            return "I built a trip plan for \(place)\(dayText)."
        }
        if !message.sections.isEmpty {
            return "I showed these results: " + message.sections.map(\.id).joined(separator: ", ") + "."
        }
        return ""
    }
}

// MARK: - Storage

extension ChatMessageState {
    var json: JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id), "role": .string(role.rawValue), "content": .string(content),
            "suggestions": .array(suggestions.map(JSONValue.string)),
            "sections": .array(sections.map { section in
                var entry: [String: JSONValue] = ["section": .string(section.id), "data": section.data, "failed": .bool(section.failed)]
                if let source = section.source { entry["source"] = .string(source.rawValue) }
                return .object(entry)
            }),
            "failed": .bool(failed),
        ]
        if let planning {
            var plan: [String: JSONValue] = ["done": .bool(planning.done)]
            if let destination = planning.destination { plan["destination"] = .string(destination) }
            if let map = planning.tripMap { plan["tripMap"] = map }
            if let itinerary = planning.itinerary { plan["comprehensiveItinerary"] = itinerary }
            if let error = planning.itineraryError { plan["itineraryError"] = .string(error) }
            object["planning"] = .object(plan)
        }
        if let importURL { object["importUrl"] = .string(importURL) }
        return .object(object)
    }

    init?(json: JSONValue) {
        guard let role = json["role"].string.flatMap(ChatRole.init(rawValue:)) else { return nil }
        let sections: [ChatSection] = (json["sections"].array ?? []).compactMap { entry in
            guard let id = entry["section"].string else { return nil }
            return ChatSection(
                id: id, data: entry["data"], source: entry["source"].string.flatMap(SectionSource.init(rawValue:)),
                failed: entry["failed"].bool ?? false)
        }
        var planning: PlanningState?
        if json["planning"].object != nil {
            let plan = json["planning"]
            planning = PlanningState(
                destination: plan["destination"].string,
                tripMap: plan["tripMap"].isNull ? nil : plan["tripMap"],
                generating: false,
                itinerary: plan["comprehensiveItinerary"].isNull ? nil : plan["comprehensiveItinerary"],
                itineraryError: plan["itineraryError"].string,
                done: true)
        }
        self.init(
            id: json["id"].string ?? UUID().uuidString, role: role, content: json["content"].string ?? "",
            suggestions: (json["suggestions"].array ?? []).compactMap(\.string), sections: sections,
            planning: planning, importURL: json["importUrl"].string, failed: json["failed"].bool ?? false)
    }
}
