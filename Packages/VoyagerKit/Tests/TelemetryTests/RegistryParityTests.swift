import Foundation
import Testing
@testable import Telemetry
import VoyagerModel

@Suite struct RegistryParityTests {
    static func registry() throws -> [String: [String: String]] {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "telemetry_registry", withExtension: "json", subdirectory: "Resources")
            ?? bundle.url(forResource: "telemetry_registry", withExtension: "json")
        let data = try Data(contentsOf: try #require(url))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["events"] as? [String: [String: String]])
    }

    static func type(_ spec: String) -> PropType? {
        switch spec {
        case "id": .token
        case "int": .int
        case "float": .float
        case "bool": .bool
        default:
            spec.hasPrefix("enum:") ? .enumeration(spec.dropFirst(5).split(separator: "|").map(String.init)) : nil
        }
    }

    static let samples: [TelemetryEvent] = [
        .appOpen, .appBackground, .screenView(route: "/chat", referrer: "/"), .screenTime(route: "/chat", ms: 1200),
        .uiTap(tid: "search.submit", route: "/"), .uiToggle(tid: "prefs.x", route: "/preferences", on: true),
        .uiChange(tid: "search.origin", route: "/"), .uiSubmit(tid: "login.form", route: "/login"),
        .searchSubmit(mode: .search, travelers: 2, nights: 7, multiCity: false),
        .searchFirstSection(ms: 900), .searchComplete(ms: 40_000, sections: 14, errors: 1),
        .searchAbandon(ms: 5_000, sections: 2), .sectionExpand(section: "hotels"), .planSelect(section: "flights"),
        .linkOut(section: "hotels", domain: "booking.com"), .share(target: "link", object: "plan"),
        .alertEvent(action: "create", kind: "fare"), .shareOpen(kind: "plan"), .shareCreate(kind: "recap", dates: "month"),
        .shareAction(kind: "savings", target: "native"), .shareRevoke(kind: "quiz"), .onboardingStep(step: 2, action: .next),
        .featureUsed(feature: "compare", page: "search"), .themeChange("dark"), .languageChange(.de),
        .consentGranted, .perf(metric: .coldStart, value: 312.5, route: "/"),
        .apiError(source: "search", status: 500),
        .alertStoryView(kind: "flight", verdict: "good"), .alertAdvice(kind: "flight", outcome: "ok"),
        .alertDropSeen(kind: "hotel", targetHit: true, via: "in_app"), .alertDigestOpen(via: "in_app"), .alertSavingsShare(target: "copy"),
        .notifSettingsView, .notifCategoryToggle(category: "price_drops", on: false), .notifQuietHoursChange(enabled: true),
        .notifCapChange(cap: 5),
        .alertQuickWatch(kind: "hotel", action: "undo", surface: "suggest"), .alertSuggest(action: "shown", count: 3),
        .alertPrefsChange(field: "quiet_hours"),
        .notifOpen(category: "trip_reminders", source: "push"),
        .socialProfileView, .socialProfileSave(visibility: "followers"), .socialFollow(state: "pending"),
        .socialBlock(on: true), .socialReport(target: "profile", reason: "spam"),
    ]

    @Test func test_everyCaseIsInRegistry() throws {
        let registry = try Self.registry()
        for sample in Self.samples {
            let wire = sample.wire
            let declared = try #require(registry[wire.name], "\(wire.name) is not in the registry")
            for (key, value) in wire.props {
                let spec = try #require(declared[key], "\(wire.name).\(key) is not declared")
                let type = try #require(Self.type(spec))
                #expect(PropsFilter.value(value, as: type) == value, "\(wire.name).\(key) fails \(spec)")
            }
        }
    }

    @Test func test_samplesCoverEveryEnumCase() {
        let names = Set(Self.samples.map(\.wire.name))
        #expect(names.count == Self.samples.count)
        #expect(names.count == 46)
    }

    @Test func test_internalSessionStartIsInRegistry() throws {
        #expect(try Self.registry()["session_start"] != nil)
    }

    @Test func test_enumRawValuesAreRegistryMembers() throws {
        let registry = try Self.registry()
        func members(_ event: String, _ key: String) throws -> Set<String> {
            guard case .enumeration(let allowed)? = Self.type(try #require(registry[event]?[key])) else { return [] }
            return Set(allowed)
        }
        #expect(Set(ExploreModeName.allCases.map(\.rawValue)) == (try members("search_submit", "mode")))
        #expect(Set(OnboardingAction.allCases.map(\.rawValue)) == (try members("onboarding_step", "action")))
        #expect(Set(PerfMetric.allCases.map(\.rawValue)).isSubset(of: try members("perf", "metric")))
        #expect(Set(AppLanguage.allCases.map(\.rawValue)) == (try members("language_change", "lang")))
        #expect(Set(TelemetryEvent.themes) == (try members("theme_change", "theme")))
        #expect(Set(TelemetryEvent.alertKinds) == (try members("alert_story_view", "kind")))
        #expect(Set(TelemetryEvent.storyVerdicts) == (try members("alert_story_view", "verdict")))
        #expect(Set(TelemetryEvent.adviceOutcomes) == (try members("alert_advice", "outcome")))
        #expect(Set(TelemetryEvent.dropVias) == (try members("alert_drop_seen", "via")))
        #expect(Set(TelemetryEvent.digestVias) == (try members("alert_digest_open", "via")))
        #expect(Set(TelemetryEvent.quickWatchActions) == (try members("alert_quick_watch", "action")))
        #expect(Set(TelemetryEvent.quickWatchSurfaces) == (try members("alert_quick_watch", "surface")))
        #expect(Set(TelemetryEvent.suggestActions) == (try members("alert_suggest", "action")))
        #expect(Set(TelemetryEvent.prefsFields) == (try members("alert_prefs_change", "field")))
        #expect(Set(TelemetryEvent.notifCategories) == (try members("notif_category_toggle", "category")))
        #expect(Set(TelemetryEvent.notifSources) == (try members("notif_open", "source")))
        #expect(Set(TelemetryEvent.notifCategories) == (try members("notif_open", "category")))
        #expect(Set(TelemetryEvent.shareKinds) == (try members("share_create", "kind")))
        #expect(Set(TelemetryEvent.shareDates) == (try members("share_create", "dates")))
        #expect(Set(TelemetryEvent.shareTargets) == (try members("share_action", "target")))
    }
}
