import Foundation

/// The `telemetry` block of `GET /api/config`.
public struct TelemetryRemoteConfig: Codable, Sendable, Hashable {
    public var enabled: Bool
    public var flushIntervalS: Int
    public var maxBatch: Int

    public init(enabled: Bool = false, flushIntervalS: Int = 15, maxBatch: Int = 50) {
        self.enabled = enabled
        self.flushIntervalS = flushIntervalS
        self.maxBatch = maxBatch
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case flushIntervalS = "flush_interval_s"
        case maxBatch = "max_batch"
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        enabled = box.lBool(.enabled) ?? false
        flushIntervalS = box.lInt(.flushIntervalS) ?? 15
        maxBatch = box.lInt(.maxBatch) ?? 50
    }
}

/// `GET /api/config`. Absent on older backends (`404`): the app then runs with everything off.
public struct ClientConfig: Codable, Sendable, Hashable {
    public var publicBaseURL: URL?
    public var telemetry: TelemetryRemoteConfig
    public var features: [String: JSONValue]

    public init(
        publicBaseURL: URL? = nil,
        telemetry: TelemetryRemoteConfig = TelemetryRemoteConfig(),
        features: [String: JSONValue] = [:]
    ) {
        self.publicBaseURL = publicBaseURL
        self.telemetry = telemetry
        self.features = features
    }

    enum CodingKeys: String, CodingKey {
        case publicBaseURL = "public_base_url"
        case telemetry, features
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        if let text = box.lString(.publicBaseURL)?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            publicBaseURL = URL(string: text)
        } else {
            publicBaseURL = nil
        }
        telemetry = box.lAny(TelemetryRemoteConfig.self, .telemetry) ?? TelemetryRemoteConfig()
        features = box.lAny([String: JSONValue].self, .features) ?? [:]
    }
}
