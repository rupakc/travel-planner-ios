import Foundation

/// Telemetry hook (Task 14). `endpoint` is a route template such as `/api/plans/:id`, never a concrete path.
/// `status` is the HTTP status, or 0 when no response arrived (network failure).
public protocol APIObserver: Sendable {
    func didFail(endpoint: String, status: Int)
}
