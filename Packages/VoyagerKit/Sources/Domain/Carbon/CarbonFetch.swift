import Foundation

/// One `POST /api/carbon/trip` outcome, as the card needs it.
public enum CarbonFetch: Sendable, Equatable {
    case loaded(CarbonReport)
    /// The route is missing or switched off (`404`): the card hides itself.
    case gone
    /// Anything else (offline, a 5xx, an unreadable answer): the card says the footprint isn't available.
    case failed
}
