import Foundation
import L10n
import Networking
import Observation
import SharedUI
import VoyagerEnv
import VoyagerModel

/// The top of the Alerts page in v2: the savings tally (`GET /alerts/summary`, stored data, no live prices needed)
/// and the calm "live checks paused" banner. Shows nothing on a backend without Alerts 2.0.
@MainActor @Observable
public final class AlertsHeaderModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case loaded(Savings)
        /// The route is off (an older backend or `alerts_api` < 2): no header at all.
        case unavailable
        case failed(String)
    }

    public private(set) var phase: Phase = .idle

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private var run = 0

    public init(env: AppEnvironment) {
        self.env = env
    }

    var savings: Savings? {
        if case .loaded(let savings) = phase { return savings }
        return nil
    }

    var features: RemoteFeatures { RemoteFeatures(config: env.clientConfig) }

    /// Alerts 2.0 stored-data routes exist (the header's gate).
    var isAvailable: Bool { env.alertsV2.isAvailable(.stored) }

    /// The banner follows `features.live_prices`. An absent key (an older backend) reads as on, like the watch list.
    var showsPausedBanner: Bool {
        guard isAvailable else { return false }
        return env.clientConfig?.features["live_prices"]?.bool == false
    }

    /// "Share savings" opens the share sheet (Phase 4): only offered when the server has share links 2.0 and there is
    /// something to share.
    var canShare: Bool { features.hasSharingV2 && (savings.map { !$0.isEmpty } ?? false) }

    public func load() async {
        guard isAvailable else {
            phase = .unavailable
            return
        }
        run += 1
        let mine = run
        if savings == nil { phase = .loading }
        do {
            let fetched = try await env.alertsV2.summary()
            guard mine == run else { return }
            phase = .loaded(fetched)
        } catch is CancellationError {
            return
        } catch {
            guard mine == run else { return }
            if error is AlertsV2Service.Unavailable {
                phase = .unavailable
            } else if savings == nil {
                phase = .failed(Self.message(error))
            }
        }
    }

    /// Shows a tally without a request (previews and snapshots).
    func show(_ savings: Savings) { phase = .loaded(savings) }

    func shareSavings() {
        guard canShare else { return }
        env.router.open(.shareSheet(.savings))
    }

    static func message(_ error: Error) -> String {
        let api = error as? APIError
        return ErrorCopy.message(kind: api?.presentationKind ?? .other, detail: api?.userFacingDetail)
    }
}
