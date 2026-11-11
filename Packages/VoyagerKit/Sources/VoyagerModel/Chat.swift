import Foundation

public struct ChatMessage: Codable, Sendable, Hashable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        role = try box.reqString(.role)
        content = box.lString(.content) ?? ""
    }

    enum CodingKeys: String, CodingKey { case role, content }
}

/// `POST /api/chat` body.
public struct ChatRequest: Codable, Sendable, Hashable {
    public var messages: [ChatMessage]
    public var selections: JSONValue
    public var searchResults: JSONValue
    public var sessionContext: JSONValue
    public var locale: AppLanguage?

    public init(
        messages: [ChatMessage],
        selections: JSONValue = .object([:]),
        searchResults: JSONValue = .object([:]),
        sessionContext: JSONValue = .object([:]),
        locale: AppLanguage? = nil
    ) {
        self.messages = messages
        self.selections = selections
        self.searchResults = searchResults
        self.sessionContext = sessionContext
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case messages, selections
        case searchResults = "search_results"
        case sessionContext = "session_context"
        case locale
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        messages = box.lAny([ChatMessage].self, .messages) ?? []
        selections = box.lValue(.selections)
        searchResults = box.lValue(.searchResults)
        sessionContext = box.lValue(.sessionContext)
        locale = box.lAny(AppLanguage.self, .locale)
    }
}
