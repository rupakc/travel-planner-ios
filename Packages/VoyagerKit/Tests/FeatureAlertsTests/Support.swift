import Foundation
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureAlerts

/// 2026-11-14 12:00 UTC: the "now" of every test and snapshot here.
let fixedNow = Date(timeIntervalSince1970: 1_794_657_600)

func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

func fare(
    _ id: Int = 1, status: String = "active", last: Double? = 454, baseline: Double? = 500, mode: String = "any_drop",
    target: Double? = nil, flexible: Int = 0, email: Bool = false, checkStatus: String? = nil
) -> FareWatch {
    FareWatch(
        id: id, originLabel: "Berlin", destinationLabel: "Lisbon", departureDate: "2026-12-01", returnDate: "2026-12-08",
        numTravelers: 2, flexibleDays: flexible, alertMode: mode, targetPrice: target, emailEnabled: email, status: status,
        baselinePrice: baseline, lastPrice: last, lowestPrice: last,
        lastCheckedAt: iso(fixedNow.addingTimeInterval(-7200)), nextCheckAt: iso(fixedNow.addingTimeInterval(36_000)),
        checkStatus: checkStatus)
}

func hotel(_ id: Int = 4, status: String = "active", last: Double? = 352) -> PriceWatch {
    PriceWatch(
        id: id, kind: .hotel, title: "Lumen Hotel", subtitle: "Lisbon · 10–14 Dec", currency: "EUR", alertMode: "below_target",
        targetPrice: 320, status: status, baselinePrice: 398, lastPrice: last, lowestPrice: last,
        lastCheckedAt: iso(fixedNow.addingTimeInterval(-86_400 * 2)), nextCheckAt: iso(fixedNow.addingTimeInterval(7200)))
}

/// The shape the server stores for a frozen estimate (price_watch.py): `status: "unavailable"`, no price, and
/// `observed: {estimate: {price, source}, frozen: true}`.
func frozenEstimateHotel(_ id: Int = 4) -> PriceWatch {
    PriceWatch(
        id: id, kind: .hotel, title: "Lumen Hotel", subtitle: "Lisbon · 10–14 Dec", currency: "EUR", alertMode: "below_target",
        targetPrice: 320, status: "active", lastCheckedAt: iso(fixedNow.addingTimeInterval(-86_400 * 2)),
        nextCheckAt: iso(fixedNow.addingTimeInterval(7200)),
        lastObservation: PriceObservation(
            status: "unavailable",
            observed: .object(["estimate": .object(["price": .number(352), "source": .string("typical")]), "frozen": .bool(true)])))
}

func activity(_ id: Int = 9) -> PriceWatch {
    PriceWatch(id: id, kind: .activity, title: "Belém walking tour", subtitle: "Lisbon", currency: "USD", status: "active")
}

@MainActor
func makeEnv(_ configure: (FakeRepositories) -> Void = { _ in }) -> (AppEnvironment, FakeRepositories) {
    let fakes = FakeRepositories()
    configure(fakes)
    return (AppEnvironment.fake(fakes: fakes), fakes)
}

@MainActor
func makeModel(
    _ env: AppEnvironment, kind: WatchKind? = nil, watchID: Int? = nil
) -> AlertsModel {
    AlertsModel(env: env, kind: kind, watchID: watchID, track: { _ in }, now: { fixedNow })
}
