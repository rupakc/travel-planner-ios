import Foundation
import Networking
import os
import Telemetry

/// Reports failed API calls as `error{kind: api}` (`apiError(source:status:)`), at most `limit` per launch.
/// `endpoint` is always a route template from `Endpoint.telemetryName`, never a concrete path.
public final class TelemetryGlue: APIObserver {
    public static let defaultLimit = 20

    private let telemetry: Telemetry
    private let limit: Int
    private let sent = OSAllocatedUnfairLock(initialState: 0)

    public init(telemetry: Telemetry, limit: Int = TelemetryGlue.defaultLimit) {
        self.telemetry = telemetry
        self.limit = limit
    }

    public func didFail(endpoint: String, status: Int) {
        let allowed = sent.withLock { count -> Bool in
            guard count < limit else { return false }
            count += 1
            return true
        }
        guard allowed else { return }
        telemetry.track(.apiError(source: endpoint, status: status))
    }

    /// How many errors were reported this launch.
    public var reportedCount: Int { sent.withLock { $0 } }
}
