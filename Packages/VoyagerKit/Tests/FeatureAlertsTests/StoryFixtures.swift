import Foundation
import Telemetry
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

/// A price point `daysAgo` days before `fixedNow`.
func point(_ daysAgo: Int, _ price: Double) -> PricePoint {
    PricePoint(at: iso(fixedNow.addingTimeInterval(-86_400 * Double(daysAgo))), price: price)
}

let goodFlightStory = PriceStory(
    kind: .flight, watchId: 1, currency: "USD", mode: "below_target", target: 430,
    points: [point(12, 500), point(10, 488), point(8, 470), point(5, 455), point(3, 462), point(1, 441)],
    baseline: 500, latest: point(1, 441), lowest: point(1, 441), typical: TypicalRange(low: 430, high: 560, source: "google"),
    verdict: .good, advice: StoryAdvice(code: .nearTarget, params: ["gap": 11]), checkedAt: iso(fixedNow.addingTimeInterval(-86_400)),
    checkedDaysAgo: 1, caught: 59)

let highHotelStory = PriceStory(
    kind: .hotel, watchId: 4, currency: "EUR", mode: "any_drop",
    points: [point(20, 320), point(16, 330), point(12, 355), point(8, 372), point(4, 390), point(0, 402)],
    baseline: 320, latest: point(0, 402), lowest: point(20, 320),
    typical: TypicalRange(low: 318, high: 360, source: "history"), verdict: .high,
    advice: StoryAdvice(code: .aboveTypical), checkedAt: iso(fixedNow), checkedDaysAgo: 0)

let pendingStory = PriceStory(
    kind: .hotel, watchId: 4, currency: "EUR", mode: "any_drop", advice: StoryAdvice(code: .pending),
    pendingFirstCheck: true, estimate: StoryEstimate(price: 352, source: "typical"))

let pausedStory = PriceStory(
    kind: .flight, watchId: 1, currency: "USD", mode: "any_drop",
    points: [point(9, 480), point(7, 470), point(6, 455)], baseline: 480, latest: point(6, 455), lowest: point(6, 455),
    typical: TypicalRange(low: 430, high: 560, source: "google"), verdict: nil,
    advice: StoryAdvice(code: .checksPaused, params: ["days": 6]), checkedAt: iso(fixedNow.addingTimeInterval(-86_400 * 6)),
    checkedDaysAgo: 6, livePrices: false)

let storyConfig = ClientConfig(features: ["alerts_api": .number(2), "price_alerts_v2": .bool(true), "live_prices": .bool(true)])

@MainActor
func storyModel(_ kind: WatchKind = .flight, id: Int = 1, track: @escaping @MainActor (TelemetryEvent) -> Void = { _ in })
    -> PriceStoryModel
{
    PriceStoryModel(env: AppEnvironment.fake(clientConfig: storyConfig), kind: kind, watchID: id, track: track, now: { fixedNow })
}
