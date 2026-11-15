import Foundation
import os
import Testing
import VoyagerModel

@testable import NotificationsCore

private final class FakeNearby: NearbyRepository, Sendable {
    struct Failure: Error {}
    private struct State {
        var requests: [NearbyRequest] = []
        var response = NearbyResponse(
            place: NearbyPlace(name: "Shibuya"), items: [.object(["name": "Meiji Shrine walk", "category": "culture"])])
        var fails = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var requests: [NearbyRequest] { state.withLock { $0.requests } }
    func set(response: NearbyResponse) { state.withLock { $0.response = response } }
    func set(fails: Bool) { state.withLock { $0.fails = fails } }

    func nearby(_ request: NearbyRequest) async throws -> NearbyResponse {
        let (answer, fails) = state.withLock { s -> (NearbyResponse, Bool) in
            s.requests.append(request)
            return (s.response, s.fails)
        }
        if fails { throw Failure() }
        return answer
    }
}

private final class Counter: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)
    var count: Int { value.withLock { $0 } }
    func bump() { value.withLock { $0 += 1 } }
}

private let copy = NearYouTemplates.Copy(fallbackTitle: { "Something nearby" }, fallbackBody: { "Open Voyager near a place" })
private let paris = NearYouLocation(lat: 48.8566, lng: 2.3522)
private let noon = Date(timeIntervalSince1970: 1_803_902_400)  // 2027-03-01 12:00 UTC

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "nearyou-test-" + UUID().uuidString) ?? .standard
}

private struct Rig {
    let nearby = FakeNearby()
    let center: FakeCenter
    let reads = Counter()
    let defaults = makeDefaults()
    let notifier: NearYouNotifier

    init(rules: NearYouRules? = NearYouRules(deviceOptIn: true), granted: Bool = true) {
        let center = FakeCenter(granted: granted)
        self.center = center
        notifier = NearYouNotifier(nearby: nearby, center: center, defaults: defaults, copy: copy) { rules }
    }

    func run(at place: NearYouLocation? = paris, phase: NearYouPhase = .onTheRoad, now: Date = noon) async -> NearYouResult {
        let reads = reads
        return await notifier.evaluate(location: { reads.bump(); return place }, phase: phase, now: now)
    }
}

@Suite struct NearYouNotifierTests {
    @Test func test_postsOnePersonalizedNotificationFromOneNearbyCall() async {
        let rig = Rig()
        #expect(await rig.run() == .posted(personalized: true))
        #expect(rig.nearby.requests.count == 1)
        let posted = rig.center.added
        #expect(posted.count == 1)
        #expect(posted.first?.title == "Something nearby" && posted.first?.body == "Shibuya: Meiji Shrine walk")
        #expect(posted.first?.fireComponents == nil && posted.first?.userInfo["route"] == "nearby")
    }

    @Test func test_requiresNearbySwitch() async {
        let off = Rig(rules: NearYouRules(deviceOptIn: true, settings: NotificationSettings(categories: [.nearby: false])))
        #expect(await off.run() == .skipped(.categoryOff))
        let device = Rig(rules: NearYouRules(deviceOptIn: false))
        #expect(await device.run() == .skipped(.deviceOptOut))
        for rig in [off, device] {
            #expect(rig.nearby.requests.isEmpty && rig.reads.count == 0 && rig.center.added.isEmpty)
        }
        let on = Rig(rules: NearYouRules(deviceOptIn: true, settings: NotificationSettings(categories: [.nearby: true])))
        #expect(await on.run() == .posted(personalized: true))
    }

    @Test func test_blockedInQuietHours() async {
        let settings = NotificationSettings(
            quietHours: QuietHoursPref(enabled: true, start: "22:00", end: "07:00"), timezone: "UTC")
        let rig = Rig(rules: NearYouRules(deviceOptIn: true, settings: settings))
        let night = noon.addingTimeInterval(11.5 * 3600)  // 23:30 UTC
        #expect(await rig.run(now: night) == .skipped(.quietHours))
        #expect(rig.nearby.requests.isEmpty && rig.reads.count == 0 && rig.center.added.isEmpty)
        #expect(await rig.run(now: noon) == .posted(personalized: true))
        let noZone = Rig(rules: NearYouRules(
            deviceOptIn: true, settings: NotificationSettings(quietHours: QuietHoursPref(enabled: true), timezone: nil)))
        #expect(await noZone.run(now: night) == .posted(personalized: true))
    }

    @Test func test_throttlePerCellAndHours() async {
        let rig = Rig()
        let here = NearYouLocation(lat: 10.0, lng: 20.0)
        let near = NearYouLocation(lat: 10.0003, lng: 20.0003)  // about 45 m away: the same 500 m cell
        let far = NearYouLocation(lat: 10.02, lng: 20.0)  // about 2 km away
        #expect(NearYouNotifier.cell(here) == NearYouNotifier.cell(near) && NearYouNotifier.cell(here) != NearYouNotifier.cell(far))
        #expect(await rig.run(at: here) == .posted(personalized: true))
        #expect(await rig.run(at: near, now: noon.addingTimeInterval(3600)) == .skipped(.throttled))
        #expect(await rig.run(at: far, now: noon.addingTimeInterval(3600)) == .posted(personalized: true))
        #expect(await rig.run(at: here, now: noon.addingTimeInterval(6 * 3600 + 1)) == .posted(personalized: true))
        #expect(rig.nearby.requests.count == 3)
    }

    @Test func test_dailyCapStillHolds() async {
        let rig = Rig(rules: NearYouRules(deviceOptIn: true, settings: NotificationSettings(dailyCap: 1)))
        #expect(await rig.run(at: NearYouLocation(lat: 10, lng: 20)) == .posted(personalized: true))
        #expect(await rig.run(at: NearYouLocation(lat: 10.02, lng: 20)) == .skipped(.gateDropped))
    }

    @Test func test_onlyDuringActiveTrip() async {
        let rig = Rig()
        #expect(await rig.run(phase: .other) == .skipped(.notOnTrip))
        #expect(rig.nearby.requests.isEmpty && rig.reads.count == 0)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        func plan(_ from: String?, _ to: String?) -> PlanSummary {
            var data: [String: JSONValue] = ["destination": "Tokyo"]
            if let from { data["departure_date"] = .string(from) }
            if let to { data["return_date"] = .string(to) }
            return PlanSummary(id: 1, name: "x", searchData: .object(data))
        }
        #expect(NearYouPhase.of(plans: [plan("2027-02-27", "2027-03-03")], now: noon, calendar: utc) == .onTheRoad)
        #expect(NearYouPhase.of(plans: [plan("2027-03-01", "2027-03-01")], now: noon, calendar: utc) == .onTheRoad)
        #expect(NearYouPhase.of(plans: [plan("2027-03-02", "2027-03-05")], now: noon, calendar: utc) == .other)
        #expect(NearYouPhase.of(plans: [plan("2027-02-20", "2027-02-28")], now: noon, calendar: utc) == .other)
        #expect(NearYouPhase.of(plans: [plan(nil, nil), plan("junk", "junk")], now: noon, calendar: utc) == .other)
    }

    @Test func test_olderServerWithoutSettingsStillFollowsDeviceSwitch() async {
        let rig = Rig(rules: NearYouRules(deviceOptIn: true, settings: nil))
        #expect(await rig.run() == .posted(personalized: true))
        let unreadable = Rig(rules: nil)
        #expect(await unreadable.run() == .skipped(.rulesUnavailable))
        #expect(unreadable.reads.count == 0)
    }

    @Test func test_noNotificationPermissionOrLocationPostsNothing() async {
        let denied = Rig(granted: false)
        #expect(await denied.run() == .skipped(.notAuthorized))
        #expect(denied.reads.count == 0 && denied.nearby.requests.isEmpty)
        let lost = Rig()
        #expect(await lost.run(at: nil) == .skipped(.noLocation))
        #expect(lost.nearby.requests.isEmpty && lost.center.added.isEmpty)
    }

    @Test func test_failedCallPostsNothingAndKeepsTheThrottleFree() async {
        let rig = Rig()
        rig.nearby.set(fails: true)
        #expect(await rig.run() == .skipped(.requestFailed))
        #expect(rig.center.added.isEmpty)
        rig.nearby.set(fails: false)
        #expect(await rig.run(now: noon.addingTimeInterval(60)) == .posted(personalized: true))
    }

    @Test func test_emptyAnswerPostsTheGenericInvitation() async {
        let rig = Rig()
        rig.nearby.set(response: NearbyResponse(place: NearbyPlace(name: "Shibuya"), items: []))
        #expect(await rig.run() == .posted(personalized: false))
        #expect(rig.center.added.first?.title == "Something nearby")
        #expect(rig.center.added.first?.body == "Open Voyager near a place")
    }

    @Test func test_noLocationInTelemetryOrNewCalls() async throws {
        let rig = Rig()
        #expect(await rig.run() == .posted(personalized: true))
        // The only call is the v1 /nearby: no sections (so no Google Maps grounding), one item asked for.
        let request = try #require(rig.nearby.requests.first)
        #expect(rig.nearby.requests.count == 1 && request.sections == nil && request.limit == 1)
        // Nothing location-like in the notification or in what was written to disk.
        let note = try #require(rig.center.added.first)
        let shown = [note.id, note.title, note.body] + note.userInfo.map { $0.key + $0.value }
        #expect(!shown.joined().contains("48.8") && !shown.joined().contains("2.35"))
        let stored = String(describing: rig.defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("voyager.") })
        #expect(!stored.contains("48.8") && !stored.contains("2.35"))
    }

    @Test func test_noAlwaysPermissionRequested() throws {
        // No always-on or background location anywhere in the app's code or project spec.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let banned = [
            "requestAlwaysAuthorization", "allowsBackgroundLocationUpdates", "startMonitoringSignificantLocationChanges",
            "startMonitoring(for", "startUpdatingLocation", "NSLocationAlways",
        ]
        var scanned = 0
        for folder in ["Packages/VoyagerKit/Sources", "App"] {
            let walker = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = walker?.nextObject() as? URL {
                guard ["swift", "plist", "entitlements"].contains(url.pathExtension) else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                scanned += 1
                for word in banned { #expect(!text.contains(word), "\(url.lastPathComponent) has \(word)") }
            }
        }
        let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        #expect(!project.contains("NSLocationAlways"))
        #expect(scanned > 50)
    }
}

@Suite struct NearYouTemplateTests {
    private let answer = NearbyResponse(
        place: NearbyPlace(name: "Shibuya"), items: [.object(["name": "  Meiji\nShrine walk "])])

    @Test func test_templateFallbackEnglish() {
        // No catalogue at all, or one without the key: the bundled English template.
        let english = "You're near Shibuya: Meiji Shrine walk is 7 min away"
        #expect(NearYouTemplates.content(for: answer, minutes: 7, catalog: nil, copy: copy).body == english)
        let other = NotificationCatalog(locale: "es", templates: ["trip_t7": "x"])
        #expect(NearYouTemplates.content(for: answer, minutes: 7, catalog: other, copy: copy).body == english)
        // A catalogue template wins, with every placeholder filled.
        let es = NotificationCatalog(locale: "es", templates: ["nearby_arrival": "Estás cerca de {place}: {item} a {minutes} min"])
        #expect(NearYouTemplates.content(for: answer, minutes: 7, catalog: es, copy: copy).body
            == "Estás cerca de Shibuya: Meiji Shrine walk a 7 min")
    }

    @Test func test_noTimeIsMadeUp() {
        // v1 items carry no walking time: the text names the place and the item and never a time.
        let content = NearYouTemplates.content(for: answer, copy: copy)
        #expect(content.body == "Shibuya: Meiji Shrine walk" && content.personalized && !content.body.contains("min"))
        let broken = NotificationCatalog(locale: "es", templates: ["nearby_arrival": "{place} {item} {unknown}"])
        #expect(NearYouTemplates.content(for: answer, minutes: 4, catalog: broken, copy: copy).body == "Shibuya: Meiji Shrine walk")
    }

    @Test func test_itemWithoutNameOrEmptyAnswerIsGeneric() {
        let blank = NearbyResponse(place: NearbyPlace(name: "Shibuya"), items: [.object(["name": "  "]), .object(["x": 1])])
        for response in [blank, NearbyResponse(), NearbyResponse(items: [])] {
            let content = NearYouTemplates.content(for: response, copy: copy)
            #expect(!content.personalized && content.title == "Something nearby" && content.body == "Open Voyager near a place")
        }
        let noPlace = NearbyResponse(items: [.object(["name": "Louvre"])])
        #expect(NearYouTemplates.content(for: noPlace, copy: copy).body == "Louvre")
    }
}
