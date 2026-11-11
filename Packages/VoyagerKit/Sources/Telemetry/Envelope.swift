import Foundation
import VoyagerModel

/// One queued event. `session` ties it to the session it happened in (a batch carries one session).
struct StoredEvent: Codable, Sendable, Equatable {
    var event: String
    var ts: Int64
    var screen: String?
    var props: [String: JSONValue]
    var session: String
}

struct EnvelopeClient: Encodable {
    var anonID: String
    var sessionID: String
    var platform = "ios"
    var appVersion: String
    var locale: String

    enum CodingKeys: String, CodingKey {
        case anonID = "anon_id", sessionID = "session_id", platform
        case appVersion = "app_version", locale
    }
}

struct EnvelopeEvent: Encodable {
    var event: String
    var ts: Int64
    var screen: String?
    var props: [String: JSONValue]
}

/// The `POST /api/telemetry` body (docs/Telemetry.md, "Envelope").
struct Envelope: Encodable {
    var client: EnvelopeClient
    var events: [EnvelopeEvent]

    init(anonID: String, appVersion: String, locale: String, batch: [StoredEvent]) {
        client = EnvelopeClient(
            anonID: anonID, sessionID: batch.first?.session ?? "", appVersion: appVersion, locale: locale
        )
        events = batch.map { EnvelopeEvent(event: $0.event, ts: $0.ts, screen: $0.screen, props: $0.props) }
    }

    /// `app_version` and `locale` must be tokens; locale at most 16 characters.
    static func safeToken(_ value: String, fallback: String, limit: Int = 64) -> String {
        guard value.utf8.count <= limit, let valid = PropsFilter.token(value) else { return fallback }
        return valid
    }
}
