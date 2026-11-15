import Foundation
import Testing

@testable import VoyagerModel

private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
}

private let example = """
    {"categories": {"price_drops": {"enabled": true}, "trip_reminders": {"enabled": false},
                    "morning_brief": {"enabled": true}, "weather": {"enabled": true},
                    "nearby": {"enabled": false}, "social": {"enabled": true}, "quiz": {"enabled": true}},
     "quiet_hours": {"enabled": true, "start": "22:00", "end": "07:00"},
     "daily_cap": 3, "timezone": "Asia/Kolkata", "quiet_hours_active": true,
     "push": {"fcm": false, "apns": true}, "devices": 2}
    """

@Suite struct NotificationSettingsDecodingTests {
    @Test func test_parsesTheContractExample() throws {
        let settings = try decode(NotificationSettings.self, example)
        #expect(!settings.isEnabled(.tripReminders) && !settings.isEnabled(.nearby))
        #expect(settings.isEnabled(.priceDrops) && settings.isEnabled(.quiz))
        #expect(settings.quietHours == QuietHoursPref(enabled: true, start: "22:00", end: "07:00"))
        #expect(settings.dailyCap == 3 && settings.timezone == "Asia/Kolkata" && settings.quietHoursActive)
        #expect(!settings.pushFCM && settings.pushAPNS && settings.devices == 2)
    }

    @Test func test_missingAndWrongTypedKeysTakeDefaults() throws {
        let settings = try decode(
            NotificationSettings.self,
            #"{"categories": {"weather": {"enabled": false}, "invented": {"enabled": false}}, "daily_cap": "5", "devices": null, "timezone": null}"#)
        #expect(!settings.isEnabled(.weather) && settings.isEnabled(.social))
        #expect(settings.categories.count == 1)
        #expect(settings.dailyCap == 5 && settings.devices == 0 && settings.timezone == nil)
        #expect(settings.quietHours.enabled == false)
        #expect(throws: DecodingError.self) { try decode(NotificationSettings.self, "[1]") }
    }

    @Test func test_patchEncodesOnlyWhatChanged() throws {
        func wire(_ patch: NotificationSettingsPatch) throws -> JSONValue {
            try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(patch))
        }
        let toggle = try wire(NotificationSettingsPatch(categories: [.quiz: false]))
        #expect(toggle == ["categories": ["quiz": ["enabled": false]]])
        let quiet = try wire(NotificationSettingsPatch(quietHours: QuietHoursPref(enabled: true, start: "23:00", end: "06:30")))
        #expect(quiet == ["quiet_hours": ["enabled": true, "start": "23:00", "end": "06:30"]])
        #expect(try wire(NotificationSettingsPatch(dailyCap: 4)) == ["daily_cap": 4])
        #expect(try wire(NotificationSettingsPatch()) == [:])
    }

    @Test func test_patchValidityMatchesTheServerRules() {
        #expect(NotificationSettingsPatch(dailyCap: 1).isValid && NotificationSettingsPatch(dailyCap: 10).isValid)
        #expect(!NotificationSettingsPatch(dailyCap: 0).isValid && !NotificationSettingsPatch(dailyCap: 11).isValid)
        #expect(NotificationSettingsPatch(quietHours: QuietHoursPref(enabled: true, start: "00:00", end: "23:59")).isValid)
        #expect(!NotificationSettingsPatch(quietHours: QuietHoursPref(enabled: true, start: "24:00", end: "07:00")).isValid)
        #expect(!NotificationSettingsPatch(quietHours: QuietHoursPref(enabled: true, start: "22:00", end: "7:00")).isValid)
        #expect(!NotificationSettingsPatch(quietHours: QuietHoursPref(enabled: true, start: "22:60", end: "07:00")).isValid)
    }

    @Test func test_mergingKeepsTheLaterEdit() {
        let first = NotificationSettingsPatch(categories: [.weather: false, .quiz: false], dailyCap: 2)
        let second = NotificationSettingsPatch(categories: [.weather: true], dailyCap: 5)
        let merged = first.merging(second)
        #expect(merged.categories == [.weather: true, .quiz: false])
        #expect(merged.dailyCap == 5 && merged.quietHours == nil)
        #expect(NotificationSettingsPatch().merging(NotificationSettingsPatch()).isEmpty)
    }

    @Test func test_everyRowKindHasACategory() {
        let cases: [(String, NotificationCategory)] = [
            ("fare_drop", .priceDrops), ("hotel_target", .priceDrops), ("trip_drop", .priceDrops),
            ("price_digest", .priceDrops), ("watch_error", .priceDrops),
            ("trip_t30", .tripReminders), ("trip_t7", .tripReminders), ("trip_t1", .tripReminders),
            ("trip_morning", .morningBrief), ("weather_rain", .weather), ("weather_cold", .weather),
            ("social_new_follower", .social), ("social_idea_comment", .social),
            ("quiz_h2h_invite", .quiz), ("quiz_daily", .quiz), ("nearby_arrival", .nearby),
        ]
        for (kind, category) in cases { #expect(NotificationCategory.of(kind: kind) == category, "\(kind)") }
        #expect(NotificationCategory.of(kind: "brand_new_kind") == nil && NotificationCategory.of(kind: nil) == nil)
        #expect(NotificationCategory.allCases.filter(\.isGameWording) == [.quiz])
    }

    @Test func test_unknownTemplateKeysAndValuesAreIgnored() throws {
        let catalog = try decode(
            NotificationCatalog.self,
            #"{"locale": "es", "templates": {"nearby_arrival": "Estás cerca de {place}", "future_key": "x", "bad": 3, "empty": ""}}"#)
        #expect(catalog.locale == "es")
        #expect(catalog.template(NotificationTemplateKey.nearbyArrival) == "Estás cerca de {place}")
        #expect(catalog.template("bad") == nil && catalog.template("empty") == nil)
        let missing = try decode(NotificationCatalog.self, "{}")
        #expect(missing.locale == "en" && missing.templates.isEmpty)
    }

    @Test func test_renderNeedsEveryPlaceholder() {
        let catalog = NotificationCatalog.bundledEnglish
        let values = ["place": "Senso-ji", "item": "Nakamise street", "minutes": "4"]
        #expect(catalog.render("nearby_arrival", values) == "You're near Senso-ji: Nakamise street is 4 min away")
        #expect(catalog.render("nearby_arrival", ["place": "Senso-ji"]) == nil)
        #expect(catalog.render("no_such_key", values) == nil)
        #expect(NotificationCatalog(templates: ["x": "Plain text"]).render("x", [:]) == "Plain text")
        #expect(NotificationCatalog(templates: ["x": "Broken {place"]).render("x", ["place": "a"]) == nil)
    }
}
