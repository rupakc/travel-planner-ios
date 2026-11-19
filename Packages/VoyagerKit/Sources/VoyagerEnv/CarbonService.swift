import Domain
import Foundation
import Networking
import VoyagerModel

/// The one door to `POST /api/carbon/trip`. It never calls the route while `features.carbon` is off (an older backend,
/// or a missing `/config`, has no footprint card), and a `404` (the feature switched off since `/config` was read)
/// turns the card off for the session instead of retrying.
@MainActor
public final class CarbonService {
    private unowned let env: AppEnvironment
    private var degraded = false

    public init(env: AppEnvironment) {
        self.env = env
    }

    /// The footprint cards show only while this is true.
    public var isAvailable: Bool { !degraded && RemoteFeatures(config: env.clientConfig).carbon }

    public func trip(_ body: JSONValue) async -> CarbonFetch {
        guard isAvailable else { return .gone }
        do {
            let answer = try await env.repos.carbon.trip(body)
            guard let report = CarbonReport(json: answer) else { return .failed }
            return .loaded(report)
        } catch {
            if case .notFound? = error as? APIError {
                degraded = true
                return .gone
            }
            return .failed
        }
    }
}
