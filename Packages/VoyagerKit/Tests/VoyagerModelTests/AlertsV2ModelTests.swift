import Foundation
import TestFixtures
import Testing

@testable import VoyagerModel

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
}

private func goldenCases(_ name: String) throws -> [JSONValue] {
    let data = try Fixtures.upstreamData("fixtures/alerts/\(name)")
    return try JSONDecoder().decode(JSONValue.self, from: data).array ?? []
}

private func isoDay(daysAgo: Int) -> String {
    let base = Date(timeIntervalSince1970: 1_794_657_600)  // 2026-11-14T12:00:00Z
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: base.addingTimeInterval(-Double(daysAgo) * 86_400))
}

/// The server decides every verdict and advice code (`story_cases.json` is its golden table). The app must map each
/// case's server answer to the right typed values and never recompute them.
@Suite struct StoryRenderCases {
    private func story(for testCase: JSONValue) throws -> PriceStory {
        let input = testCase["input"]
        let expected = testCase["expected"]
        let points: [JSONValue] = (input["points"].array ?? []).map {
            .object(["at": .string(isoDay(daysAgo: $0["days_ago"].int ?? 0)), "price": $0["price"]])
        }
        var object: [String: JSONValue] = [
            "kind": input["kind"], "watch_id": 1, "currency": input["currency"],
            "mode": input["target"].isNull ? "any_drop" : "below_target", "target": input["target"],
            "points": .array(points), "typical": expected["typical"], "verdict": expected["verdict"],
            "advice": expected["advice"], "checked_days_ago": input["checked_days_ago"],
            "pending_first_check": input["pending_first_check"], "estimate": input["estimate"],
            "live_prices": input["live_prices"],
        ]
        if let last = (input["points"].array ?? []).last, let first = (input["points"].array ?? []).first {
            object["latest"] = .object(["at": .string(isoDay(daysAgo: last["days_ago"].int ?? 0)), "price": expected["latest"]])
            object["lowest"] = .object(["at": .string(isoDay(daysAgo: first["days_ago"].int ?? 0)), "price": expected["lowest"]])
            object["baseline"] = first["price"]
        }
        let data = try JSONEncoder().encode(JSONValue.object(object))
        return try JSONDecoder().decode(PriceStory.self, from: data)
    }

    @Test func test_goldenStoryCases() throws {
        let cases = try goldenCases("story_cases.json")
        #expect(cases.count == 25)
        for testCase in cases {
            let name = testCase["name"].string ?? "?"
            let expected = testCase["expected"]
            let story = try story(for: testCase)
            #expect(story.advice?.code.wire == expected["advice"]["code"].string, "\(name): advice code")
            #expect(story.advice?.code.isKnown == true, "\(name): known code")
            let wantedParams = (expected["advice"]["params"].object ?? [:]).compactMapValues(\.double)
            #expect(story.advice?.params == wantedParams, "\(name): params")
            #expect(story.verdict?.rawValue == expected["verdict"].string, "\(name): verdict")
            #expect(story.typical?.low == expected["typical"]["low"].double, "\(name): typical low")
            #expect(story.typical?.high == expected["typical"]["high"].double, "\(name): typical high")
            #expect(story.typical?.source == expected["typical"]["source"].string, "\(name): typical source")
            #expect(story.latest?.price == expected["latest"].double, "\(name): latest")
            #expect(story.lowest?.price == expected["lowest"].double, "\(name): lowest")
            #expect(story.points.count == testCase["input"]["points"].array?.count, "\(name): points")
            #expect(story.hasObservedPrice == !expected["latest"].isNull, "\(name): observed")
        }
    }

    @Test func test_estimateIsNeverAPointOrTheLatest() throws {
        let cases = try goldenCases("story_cases.json")
        let estimateOnly = try #require(cases.first { $0["name"].string == "estimate_only" })
        let story = try story(for: estimateOnly)
        #expect(story.estimate?.price == 180)
        #expect(story.points.isEmpty && story.latest == nil && story.verdict == nil && !story.hasObservedPrice)
        #expect(story.advice?.code == .pending)
    }
}

@Suite struct SavingsCases {
    @Test func test_goldenSavingsCases() throws {
        let cases = try goldenCases("savings_cases.json")
        #expect(cases.count == 12)
        for testCase in cases {
            let name = testCase["name"].string ?? "?"
            let expected = testCase["expected"]
            let data = try JSONEncoder().encode(expected)
            let savings = try JSONDecoder().decode(Savings.self, from: data)
            #expect(savings.totalUSD == expected["total_usd"].double, "\(name): total")
            #expect(savings.byCurrency == (expected["by_currency"].object ?? [:]).compactMapValues(\.double), "\(name): currencies")
            #expect(savings.dropsCaught == expected["drops_caught"].int, "\(name): drops")
            #expect(savings.targetsHit == expected["targets_hit"].int, "\(name): targets")
            #expect(savings.watchesActive == expected["watches_active"].int, "\(name): active")
            #expect(savings.milestones == expected["milestones"].array?.compactMap(\.int), "\(name): milestones")
            #expect(savings.nextMilestone == expected["next_milestone"].int, "\(name): next milestone")
            #expect(savings.progressPct == expected["progress_pct"].int, "\(name): progress")
            #expect(savings.since == expected["since"].string, "\(name): since")
            #expect(savings.best?.caught == expected["best"]["caught"].double, "\(name): best caught")
            #expect(savings.best?.watchId == expected["best"]["watch_id"].int, "\(name): best id")
            #expect(savings.best?.kind?.rawValue == expected["best"]["kind"].string, "\(name): best kind")
            #expect(savings.best?.currency == expected["best"]["currency"].string, "\(name): best currency")
            #expect(savings.isEmpty == (expected["total_usd"].double == 0 && (expected["by_currency"].object ?? [:]).isEmpty), "\(name): empty")
        }
    }

    @Test func test_byCurrencyIsNotConverted() throws {
        let savings = try decode(
            Savings.self, #"{"total_usd": 245, "by_currency": {"EUR": 12.0, "GBP": "7.5", "JPY": 0}, "milestones": [50, 200, 1000]}"#)
        #expect(savings.totalUSD == 245)
        #expect(savings.byCurrency == ["EUR": 12, "GBP": 7.5])
        #expect(savings.currencyLines.map(\.code) == ["EUR", "GBP"])
    }
}

@Suite struct AlertsV2DecodingTests {
    @Test func test_storyExampleFromTheContract() throws {
        let story = try decode(
            PriceStory.self,
            """
            {"kind": "flight", "watch_id": 7, "currency": "USD", "mode": "below_target", "target": 380.0,
             "points": [{"at": "2026-11-01T08:00:00Z", "price": 455.0}, {"at": "2026-11-08T08:00:00Z", "price": 412.0}],
             "baseline": 455.0, "latest": {"at": "2026-11-08T08:00:00Z", "price": 412.0},
             "lowest": {"at": "2026-11-08T08:00:00Z", "price": 398.0},
             "typical": {"low": 390.0, "high": 520.0, "source": "google"},
             "verdict": "good", "advice": {"code": "near_target", "params": {"gap": 32.0}},
             "checked_at": "2026-11-08T08:00:00Z", "checked_days_ago": 0, "next_check_at": "2026-11-09T08:00:00Z",
             "pending_first_check": false, "estimate": null, "caught": 57.0, "live_prices": true}
            """)
        #expect(story.kind == .flight && story.watchId == 7 && story.mode == "below_target")
        #expect(story.target == 380 && story.points.count == 2 && story.baseline == 455)
        #expect(story.verdict == .good && story.advice?.code == .nearTarget && story.advice?.gap == 32)
        #expect(story.checkedDaysAgo == 0 && story.caught == 57 && story.livePrices && !story.pendingFirstCheck)
        #expect(story.estimate == nil && story.typical?.source == "google")
    }

    @Test func test_pendingStoryDecodes() throws {
        let story = try decode(
            PriceStory.self,
            """
            {"kind": "hotel", "watch_id": 3, "currency": "EUR", "mode": "any_drop", "target": null, "points": [],
             "baseline": null, "latest": null, "lowest": null, "typical": null, "verdict": null,
             "advice": {"code": "pending", "params": {}}, "checked_at": null, "checked_days_ago": null,
             "next_check_at": null, "pending_first_check": true, "estimate": null, "caught": null, "live_prices": true}
            """)
        #expect(story.pendingFirstCheck && story.latest == nil && story.points.isEmpty && story.advice?.code == .pending)
    }

    @Test func test_unknownAdviceCodeIgnored() throws {
        let story = try decode(
            PriceStory.self,
            #"{"watch_id": 1, "verdict": "amazing", "advice": {"code": "buy_now", "params": {"x": 1}}, "extra": [1]}"#)
        #expect(story.advice?.code == .unknown("buy_now") && story.advice?.code.isKnown == false)
        #expect(story.verdict == nil)
        #expect(AdviceCode(wire: "checks_paused") == .checksPaused && AdviceCode.checksPaused.wire == "checks_paused")
    }

    @Test func test_storyToleratesBadPointsAndNumbersAsStrings() throws {
        let story = try decode(
            PriceStory.self,
            #"{"watch_id": "9", "target": "380", "points": [{"at": "a", "price": "412"}, {"at": "b"}, 5], "checked_days_ago": "2"}"#)
        #expect(story.watchId == 9 && story.target == 380 && story.checkedDaysAgo == 2)
        #expect(story.points == [PricePoint(at: "a", price: 412)])
    }

    @Test func test_lenientNumber() throws {
        #expect(try decode([LenientNumber].self, #"[1, 2.5, "3", "4.5"]"#).map(\.value) == [1, 2.5, 3, 4.5])
        #expect(throws: DecodingError.self) { try decode(LenientNumber.self, #""""#) }
        #expect(throws: DecodingError.self) { try decode(LenientNumber.self, "null") }
    }

    @Test func test_pendingWatchDecodes() throws {
        let fare = try decode(FareWatch.self, #"{"id": 5, "status": "active", "last_price": null, "pending_first_check": true}"#)
        #expect(fare.pendingFirstCheck == true && fare.lastPrice == nil)
        let price = try decode(PriceWatch.self, #"{"id": 6, "kind": "hotel", "last_price": null, "pending_first_check": true}"#)
        #expect(price.pendingFirstCheck == true && price.lastPrice == nil)
        let old = try decode(FareWatch.self, #"{"id": 7, "last_price": 400}"#)
        #expect(old.pendingFirstCheck == nil)
    }

    @Test func test_prefsExampleAndWritableSubset() throws {
        let prefs = try decode(
            AlertPrefs.self,
            """
            {"digest_weekly": false, "digest_push": false, "digest_day": 1, "instant": "all",
             "quiet_hours": {"enabled": true, "start": "22:00", "end": "07:00"},
             "daily_cap": {"flight": 3, "hotel": 3, "activity": 3, "trip": 3}, "group_window_min": 15,
             "timezone": "Asia/Kolkata", "quiet_hours_active": true}
            """)
        #expect(prefs.quietHours == QuietHoursPref(enabled: true, start: "22:00", end: "07:00"))
        #expect(prefs.timezone == "Asia/Kolkata" && prefs.quietHoursActive && prefs.dailyCap[.hotel] == 3)
        let body = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(prefs.writable))
        #expect(body["timezone"].isNull && body["quiet_hours_active"].isNull)
        #expect(body["digest_day"].int == 1 && body["instant"].string == "all" && body["quiet_hours"]["end"].string == "07:00")
        let partial = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(AlertPrefsPatch(instant: .targetsOnly)))
        #expect(partial.object?.keys.sorted() == ["instant"] && partial["instant"].string == "targets_only")
        #expect(try decode(AlertPrefs.self, #"{"timezone": null, "instant": "weird"}"#).instant == .all)
    }

    @Test func test_quickWatchEncodesAndDecodes() throws {
        let request = QuickWatchRequest(
            kind: .hotel, title: String(repeating: "t", count: 200), subtitle: nil, spec: ["name": "Lumen"], planId: 4,
            surface: .suggest)
        let body = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
        #expect(body["kind"].string == "hotel" && body["plan_id"].int == 4 && body["surface"].string == "suggest")
        #expect(body["title"].string?.count == 120 && body["spec"]["name"].string == "Lumen")
        let result = try decode(
            QuickWatchResult.self,
            #"{"kind": "hotel", "watch": {"id": 11, "kind": "hotel", "last_price": null, "pending_first_check": true}, "existing": false}"#)
        #expect(result.kind == .hotel && result.watchID == 11 && !result.existing)
        if case .price(let watch) = result.watch {
            #expect(watch.pendingFirstCheck == true)
        } else {
            Issue.record("expected a price watch")
        }
        let fare = try decode(QuickWatchResult.self, #"{"kind": "flight", "watch": {"id": 2}, "existing": true}"#)
        #expect(fare.existing)
        if case .fare = fare.watch {} else { Issue.record("expected a fare watch") }
    }

    @Test func test_adviceAndSuggestions() throws {
        let tip = try decode(AdviceTip.self, #"{"tip": "Wait.", "source": "ai", "generated_at": "2026-11-08T08:00:00Z", "cached": true}"#)
        #expect(tip.tip == "Wait." && tip.cached)
        let list = try decode(
            WatchSuggestions.self,
            """
            {"suggestions": [
              {"kind": "flight", "title": "NYC to Lisbon", "subtitle": "Dec", "spec": {"origin": "NYC"}, "reason": "selected_in_plan", "already_watching": false},
              {"kind": "hotel", "title": "Lumen", "spec": {}, "reason": "something_new", "already_watching": true},
              {"kind": "boat", "title": "bad kind"}, 7],
             "live_prices": false}
            """)
        #expect(list.suggestions.map(\.title) == ["NYC to Lisbon", "Lumen"])
        #expect(list.suggestions[0].reason == .selectedInPlan && list.suggestions[1].reason == .unknown("something_new"))
        #expect(list.suggestions[1].alreadyWatching && !list.livePrices)
    }

    @Test func test_notificationDropGameDigestAndGroupCount() throws {
        let drop = try decode(
            AppNotification.self,
            """
            {"id": 1, "kind": "fare_drop", "title": "t", "body": "b", "data": {
              "drop": {"from": 455.0, "to": 412.0, "amount": 43.0, "pct": 9.5, "currency": "USD", "target_hit": true, "observed": true, "future": 1},
              "game": {"xp": 150, "awards": [{"rule": "price_drop", "points": 10}, {"rule": "target_hit", "points": 25}],
                       "badges": [{"id": "deal_hunter", "earned_at": "2026-11-11T10:00:00Z"}], "level_up": {"from": 1, "to": 2}},
              "group_count": "3"}}
            """)
        #expect(drop.dropData == DropData(from: 455, to: 412, amount: 43, pct: 9.5, currency: "USD", targetHit: true, observed: true))
        let game = try #require(drop.gameDelta)
        #expect(game.xp == 150 && game.awardedPoints == 35 && game.badges.map(\.id) == ["deal_hunter"])
        #expect(game.levelUp == GameDelta.LevelUp(from: 1, to: 2))
        #expect(drop.groupCount == 3 && !drop.isPriceDigest)

        let plain = try decode(AppNotification.self, #"{"id": 2, "kind": "fare_drop", "data": {"game": null}}"#)
        #expect(plain.dropData == nil && plain.gameDelta == nil && plain.digest == nil && plain.groupCount == nil)

        let digest = try decode(
            AppNotification.self,
            """
            {"id": 3, "kind": "price_digest", "data": {"digest": {"week": "2026-W46", "watches": [
              {"kind": "hotel", "watch_id": 3, "title": "Lumen", "latest": 352, "change_7d": -12.5, "lowest": 340, "checked_at": "2026-11-13T08:00:00Z"},
              {"kind": "mystery", "watch_id": "x"}, 5],
             "savings": {"total_usd": 43, "by_currency": {}, "milestones": [50, 200, 1000], "next_milestone": 50}}}}
            """)
        let data = try #require(digest.digest)
        #expect(digest.isPriceDigest && data.week == "2026-W46" && data.watches.count == 2)
        #expect(data.watches[0] == DigestWatch(kind: .hotel, watchId: 3, title: "Lumen", latest: 352, change7d: -12.5, lowest: 340, checkedAt: "2026-11-13T08:00:00Z"))
        #expect(data.watches[1].kind == nil && data.watches[1].watchId == nil)
        #expect(data.savings?.totalUSD == 43)
    }

    @Test func test_unobservedDropIsRefused() throws {
        let row = try decode(AppNotification.self, #"{"id": 1, "kind": "fare_drop", "title": "t", "body": "b", "data": {"drop": {"amount": 5, "observed": false}}}"#)
        #expect(row.dropData == nil)
    }

    @Test func test_quickWatchTitleNeedsOneCharacter() {
        #expect(!QuickWatchRequest(kind: .hotel, title: "   ", spec: .null, surface: .results).isValid)
        #expect(QuickWatchRequest(kind: .hotel, title: " A ", spec: .null, surface: .results).title == "A")
    }

    @Test func test_v1BackendKeepsLegacyScreens() {
        let old = RemoteFeatures(features: ["accounts": .bool(true)])
        #expect(!old.hasAlertsV2 && !old.showsQuickWatch)
        let keyless = RemoteFeatures(alertsAPI: 2, priceAlertsV2: true, livePrices: false)
        #expect(keyless.hasAlertsV2 && !keyless.showsQuickWatch)
    }
}
