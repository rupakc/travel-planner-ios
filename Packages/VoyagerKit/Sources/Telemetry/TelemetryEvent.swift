import Foundation
import VoyagerModel

public enum ExploreModeName: String, Sendable, CaseIterable {
    case search, chat, compare, link, discover
}

public enum OnboardingAction: String, Sendable, CaseIterable {
    case view, next, skip, done
}

/// The subset of the registry's `perf.metric` enum that iOS emits.
public enum PerfMetric: String, Sendable, CaseIterable {
    case ttfb
    case coldStart = "cold_start"
    case longTask = "long_task"
}

/// Every event iOS emits. Names and props are exactly the registry's (`Upstream/telemetry_registry.json`);
/// `session_start` is emitted internally. Free-form strings are validated by `PropsFilter` when the event
/// is converted to its wire form, so a bad id drops the prop instead of leaking text.
public enum TelemetryEvent: Sendable {
    case appOpen
    case appBackground
    case screenView(route: String, referrer: String?)
    case screenTime(route: String, ms: Int)
    case uiTap(tid: String, route: String)
    case uiToggle(tid: String, route: String, on: Bool)
    case uiChange(tid: String, route: String)
    case uiSubmit(tid: String, route: String)
    case searchSubmit(mode: ExploreModeName, travelers: Int, nights: Int, multiCity: Bool)
    case searchFirstSection(ms: Int)
    case searchComplete(ms: Int, sections: Int, errors: Int)
    case searchAbandon(ms: Int, sections: Int)
    case sectionExpand(section: String)
    case planSelect(section: String)
    case linkOut(section: String, domain: String)
    case share(target: String, object: String)
    case alertEvent(action: String, kind: String)
    /// Share links 2.0. `kind` is the registry's `plan|recap|savings|quiz|status`, `dates` `hidden|month|exact`, `target`
    /// `native|copy|download|...`; a value outside its enum drops the prop.
    case shareOpen(kind: String)
    case shareCreate(kind: String, dates: String)
    case shareAction(kind: String, target: String)
    case shareRevoke(kind: String)
    case onboardingStep(step: Int, action: OnboardingAction)
    case featureUsed(feature: String, page: String)
    case themeChange(String)
    case languageChange(AppLanguage)
    case consentGranted
    case perf(metric: PerfMetric, value: Double, route: String)
    case apiError(source: String, status: Int)
}

/// A validated event, ready to queue.
struct WireEvent: Sendable {
    var name: String
    var props: [String: JSONValue]
    /// The route template for events that carry one (the envelope's optional `screen`).
    var screen: String? { props["route"]?.string }
}

extension TelemetryEvent {
    static let themes = ["system", "light", "dark"]
    static let shareKinds = ["plan", "recap", "savings", "quiz", "status"]
    static let shareDates = ["hidden", "month", "exact"]
    static let shareTargets = ["native", "copy", "download", "x", "facebook", "whatsapp", "linkedin"]

    var wire: WireEvent {
        var props: [String: JSONValue] = [:]
        func token(_ key: String, _ value: String) {
            if let valid = PropsFilter.token(value) { props[key] = .string(valid) }
        }
        func choice(_ key: String, _ value: String, in allowed: [String]) {
            if let valid = PropsFilter.enum(value, allowed: allowed) { props[key] = .string(valid) }
        }
        func int(_ key: String, _ value: Int) {
            if let valid = PropsFilter.int(value) { props[key] = .number(Double(valid)) }
        }
        let name: String
        switch self {
        case .appOpen: name = "app_open"
        case .appBackground: name = "app_background"
        case .screenView(let route, let referrer):
            name = "screen_view"
            token("route", route)
            if let referrer { token("referrer_route", referrer) }
        case .screenTime(let route, let ms):
            name = "screen_time"
            token("route", route)
            int("ms", ms)
        case .uiTap(let tid, let route):
            name = "ui_tap"
            token("tid", tid)
            token("route", route)
        case .uiToggle(let tid, let route, let on):
            name = "ui_toggle"
            token("tid", tid)
            token("route", route)
            props["on"] = .bool(on)
        case .uiChange(let tid, let route):
            name = "ui_change"
            token("tid", tid)
            token("route", route)
        case .uiSubmit(let tid, let route):
            name = "ui_submit"
            token("tid", tid)
            token("route", route)
        case .searchSubmit(let mode, let travelers, let nights, let multiCity):
            name = "search_submit"
            props["mode"] = .string(mode.rawValue)
            int("travelers", travelers)
            int("nights", nights)
            props["multi_city"] = .bool(multiCity)
        case .searchFirstSection(let ms):
            name = "search_first_section"
            int("ms", ms)
        case .searchComplete(let ms, let sections, let errors):
            name = "search_complete"
            int("ms", ms)
            int("sections", sections)
            int("errors", errors)
        case .searchAbandon(let ms, let sections):
            name = "search_abandon"
            int("ms", ms)
            int("sections", sections)
        case .sectionExpand(let section):
            name = "section_expand"
            token("section", section)
        case .planSelect(let section):
            name = "plan_select"
            token("section", section)
        case .linkOut(let section, let domain):
            name = "link_out"
            token("section", section)
            token("domain", domain)
        case .share(let target, let object):
            name = "share"
            token("target", target)
            token("object", object)
        case .alertEvent(let action, let kind):
            name = "alert_event"
            token("action", action)
            token("kind", kind)
        case .shareOpen(let kind):
            name = "share_open"
            choice("kind", kind, in: Self.shareKinds)
        case .shareCreate(let kind, let dates):
            name = "share_create"
            choice("kind", kind, in: Self.shareKinds)
            choice("dates", dates, in: Self.shareDates)
        case .shareAction(let kind, let target):
            name = "share_action"
            choice("kind", kind, in: Self.shareKinds)
            choice("target", target, in: Self.shareTargets)
        case .shareRevoke(let kind):
            name = "share_revoke"
            choice("kind", kind, in: Self.shareKinds)
        case .onboardingStep(let step, let action):
            name = "onboarding_step"
            int("step", step)
            props["action"] = .string(action.rawValue)
        case .featureUsed(let feature, let page):
            name = "feature_used"
            token("feature", feature)
            token("page", page)
        case .themeChange(let theme):
            name = "theme_change"
            if let valid = PropsFilter.enum(theme, allowed: Self.themes) { props["theme"] = .string(valid) }
        case .languageChange(let language):
            name = "language_change"
            props["lang"] = .string(language.rawValue)
        case .consentGranted:
            name = "consent"
            props["choice"] = .string("granted")
        case .perf(let metric, let value, let route):
            name = "perf"
            props["metric"] = .string(metric.rawValue)
            if let valid = PropsFilter.float(value) { props["value"] = .number(valid) }
            token("route", route)
        case .apiError(let source, let status):
            name = "error"
            props["kind"] = .string("api")
            token("source", source)
            int("status", status)
        }
        return WireEvent(name: name, props: props)
    }
}
