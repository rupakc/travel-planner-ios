import Foundation

/// `GET /health`. A flag the backend does not send is nil, which clients treat as off.
public struct Health: Codable, Sendable, Hashable {
    public var status: String?
    public var service: String?
    public var serpapiConfigured: Bool?
    public var fareWatchAvailable: Bool?
    public var emailAlertsAvailable: Bool?
    public var pushConfigured: Bool?

    public init(
        status: String? = nil,
        service: String? = nil,
        serpapiConfigured: Bool? = nil,
        fareWatchAvailable: Bool? = nil,
        emailAlertsAvailable: Bool? = nil,
        pushConfigured: Bool? = nil
    ) {
        self.status = status
        self.service = service
        self.serpapiConfigured = serpapiConfigured
        self.fareWatchAvailable = fareWatchAvailable
        self.emailAlertsAvailable = emailAlertsAvailable
        self.pushConfigured = pushConfigured
    }

    enum CodingKeys: String, CodingKey {
        case status
        case service
        case serpapiConfigured = "serpapi_configured"
        case fareWatchAvailable = "fare_watch_available"
        case emailAlertsAvailable = "email_alerts_available"
        case pushConfigured = "push_configured"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        status = box.lString(.status)
        service = box.lString(.service)
        serpapiConfigured = box.lBool(.serpapiConfigured)
        fareWatchAvailable = box.lBool(.fareWatchAvailable)
        emailAlertsAvailable = box.lBool(.emailAlertsAvailable)
        pushConfigured = box.lBool(.pushConfigured)
    }
}
