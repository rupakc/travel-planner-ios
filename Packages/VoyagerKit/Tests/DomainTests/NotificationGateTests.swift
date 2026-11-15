import Foundation
import Testing
import VoyagerModel

@testable import Domain

@Suite struct NotificationGateTests {
    /// 2026-11-12T18:00:00Z is 23:30 in Kolkata (inside 22:00-07:00); the window ends at 2026-11-13T01:30:00Z.
    private let night = Self.date("2026-11-12T18:00:00Z")
    private let noon = Self.date("2026-11-12T08:00:00Z")

    private static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    private func settings(
        off: [NotificationCategory] = [], quiet: Bool = true, timezone: String? = "Asia/Kolkata", cap: Int = 3
    ) -> NotificationSettings {
        var categories: [NotificationCategory: Bool] = [:]
        for category in off { categories[category] = false }
        return NotificationSettings(
            categories: categories, quietHours: QuietHoursPref(enabled: quiet, start: "22:00", end: "07:00"), dailyCap: cap,
            timezone: timezone)
    }

    private func row(_ kind: String, data: JSONValue = .null) -> AppNotification {
        AppNotification(id: 1, kind: kind, title: "t", body: "b", data: data)
    }

    @Test func test_gateCategoryOff() {
        let off = settings(off: [.priceDrops, .tripReminders, .weather])
        #expect(NotificationGate.decide(row: row("fare_drop"), settings: off, now: noon) == .drop)
        #expect(NotificationGate.decide(row: row("trip_t7"), settings: off, now: noon) == .drop)
        #expect(NotificationGate.decide(row: row("weather_rain"), settings: off, now: noon) == .drop)
        #expect(NotificationGate.decide(row: row("trip_morning"), settings: off, now: noon) == .deliverNow)
    }

    @Test func test_unknownKindIsNeverShownLocally() {
        #expect(NotificationGate.decide(row: row("brand_new_kind"), settings: settings(), now: noon) == .drop)
        #expect(NotificationGate.decide(row: AppNotification(id: 2), settings: settings(), now: noon) == .drop)
    }

    @Test func test_hiddenGameDropsQuizRows() {
        let quiz = row("quiz_h2h_invite")
        #expect(NotificationGate.decide(row: quiz, settings: settings(), now: noon, showsGame: false) == .drop)
        #expect(NotificationGate.decide(row: quiz, settings: settings(), now: noon, showsGame: true) == .deliverNow)
        #expect(NotificationGate.decide(row: row("social_new_follower"), settings: settings(), now: noon, showsGame: false) == .deliverNow)
    }

    @Test func test_gateHoldsToWindowEnd() {
        let expected = Self.date("2026-11-13T01:30:00Z")
        #expect(NotificationGate.decide(row: row("fare_drop"), settings: settings(), now: night) == .holdUntil(expected))
        #expect(NotificationGate.decide(row: row("trip_t1"), settings: settings(), now: night) == .holdUntil(expected))
        #expect(NotificationGate.decide(row: row("trip_t1"), settings: settings(quiet: false), now: night) == .deliverNow)
        // No account time zone: quiet hours are not applied.
        #expect(NotificationGate.decide(row: row("trip_t1"), settings: settings(timezone: nil), now: night) == .deliverNow)
        #expect(NotificationGate.decide(row: row("trip_t1"), settings: settings(), now: noon) == .deliverNow)
    }

    @Test func test_aHoldOverTwelveHoursIsDropped() {
        let long = NotificationSettings(
            quietHours: QuietHoursPref(enabled: true, start: "08:00", end: "23:00"), timezone: "UTC")
        // 08:30 UTC: the window ends in 14.5 h.
        let now = Self.date("2026-11-12T08:30:00Z")
        #expect(NotificationGate.decide(row: row("trip_t7"), settings: long, now: now) == .drop)
    }

    @Test func test_gateCapExemptForPriceDrops() {
        let capped = settings(cap: 1)
        #expect(NotificationGate.decide(row: row("trip_t7"), settings: capped, now: noon, deliveredToday: 1) == .drop)
        #expect(NotificationGate.decide(row: row("trip_t7"), settings: capped, now: noon, deliveredToday: 0) == .deliverNow)
        // A price drop ignores `daily_cap`; the per-kind cap of the alert prefs applies instead.
        let prefs = AlertPrefs(dailyCap: DailyCaps(flight: 2, hotel: 3, activity: 3, trip: 3))
        let drop = row("fare_drop", data: ["kind": "flight"])
        #expect(NotificationGate.decide(row: drop, settings: capped, prefs: prefs, now: noon, deliveredToday: 1) == .deliverNow)
        #expect(NotificationGate.decide(row: drop, settings: capped, prefs: prefs, now: noon, deliveredToday: 2) == .drop)
        #expect(NotificationGate.decide(row: drop, settings: capped, now: noon, deliveredToday: 50) == .deliverNow)
        #expect(NotificationGate.decide(row: row("price_digest"), settings: capped, prefs: prefs, now: noon, deliveredToday: 50) == .deliverNow)
    }

    @Test func test_priceCapUsesTheWatchKind() {
        let prefs = AlertPrefs(dailyCap: DailyCaps(flight: 9, hotel: 1, activity: 9, trip: 9))
        let hotel = row("hotel_drop", data: ["watch_kind": "hotel"])
        #expect(NotificationGate.decide(row: hotel, settings: settings(), prefs: prefs, now: noon, deliveredToday: 1) == .drop)
        // No data: the kind prefix says which watch it is.
        #expect(NotificationGate.decide(row: row("hotel_drop"), settings: settings(), prefs: prefs, now: noon, deliveredToday: 1) == .drop)
        #expect(NotificationGate.decide(row: row("fare_drop"), settings: settings(), prefs: prefs, now: noon, deliveredToday: 1) == .deliverNow)
    }

    @Test func test_gateTargetsOnly() {
        let prefs = AlertPrefs(instant: .targetsOnly)
        let plain = row("fare_drop", data: ["drop": ["amount": 40, "target_hit": false]])
        let hit = row("fare_drop", data: ["drop": ["amount": 40, "target_hit": true]])
        let target = row("hotel_target")
        #expect(NotificationGate.decide(row: plain, settings: settings(), prefs: prefs, now: noon) == .drop)
        #expect(NotificationGate.decide(row: hit, settings: settings(), prefs: prefs, now: noon) == .deliverNow)
        #expect(NotificationGate.decide(row: target, settings: settings(), prefs: prefs, now: noon) == .deliverNow)
        #expect(NotificationGate.decide(row: plain, settings: settings(), prefs: AlertPrefs(instant: .all), now: noon) == .deliverNow)
        // targets_only never silences a trip reminder.
        #expect(NotificationGate.decide(row: row("trip_t7"), settings: settings(), prefs: prefs, now: noon) == .deliverNow)
    }
}
