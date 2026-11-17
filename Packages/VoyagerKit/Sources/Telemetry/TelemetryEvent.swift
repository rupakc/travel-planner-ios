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
    /// Price alerts 2.0: a price story was shown (`verdict` is great|good|typical|high|none) and the AI timing tip.
    case alertStoryView(kind: String, verdict: String)
    case alertAdvice(kind: String, outcome: String)
    /// A drop moment was shown (`via` is in_app|push|email) and the weekly digest was opened (`via` is in_app|email_link).
    case alertDropSeen(kind: String, targetHit: Bool, via: String)
    case alertDigestOpen(via: String)
    /// A one-tap watch (`action` add|undo|exists|blocked, `surface` results|chat|trip|suggest), the suggestions sheet
    /// (`action` shown|accepted|dismissed, `count` of suggestions) and an alert preference that changed (`field`
    /// digest|quiet_hours|instant|cap|group).
    case alertQuickWatch(kind: String, action: String, surface: String)
    case alertSuggest(action: String, count: Int)
    case alertPrefsChange(field: String)
    /// A savings share went out (`target` is native|copy|download).
    case alertSavingsShare(target: String)
    /// Notifications 2.0: the settings screen was opened, a category switched (`category` is a
    /// `NotificationCategory` raw value), quiet hours changed, the daily cap changed.
    case notifSettingsView
    case notifCategoryToggle(category: String, on: Bool)
    case notifQuietHoursChange(enabled: Bool)
    case notifCapChange(cap: Int)
    /// A notification was opened: `category` is a `NotificationCategory` raw value, `source` is `push|inapp`.
    case notifOpen(category: String, source: String)
    /// Social ideas feed (Phase 5). Props are enums or bools only: never a handle, id, caption or comment text.
    /// `scope` is `for_you|following|new`, `kind` `plan|recap`, `reason` and `target` the report enums.
    case socialFeedView(scope: String)
    case socialIdeaOpen
    case socialIdeaLike(on: Bool)
    case socialIdeaSave
    case socialIdeaPublish(kind: String)
    case socialComment
    /// Social profiles (Phase 5): a profile was opened (own or public), saved (`visibility` private|followers|public),
    /// a follow changed (`state` following|pending|none), a block toggled (`on`), a report sent (`target`
    /// idea|comment|profile, `reason` as the report sheet's reasons). No handle ever goes in.
    case socialProfileView
    case socialProfileSave(visibility: String)
    case socialFollow(state: String)
    case socialBlock(on: Bool)
    case socialReport(target: String, reason: String)
    /// Play (Phase 5): the hub was opened; a quiz started (`mode` daily|pack|challenge|h2h, `pack` flags|capitals|
    /// landmarks|cuisine|none); a question answered (`elapsedS` is the server's elapsed time); a quiz finished
    /// (`correct` out of five). Never a handle, session id or answer.
    case playStateView
    case playQuizStart(mode: String, pack: String)
    case playQuizAnswer(correct: Bool, elapsedS: Int)
    case playQuizDone(correct: Int, mode: String)
    /// Play, head-to-head, boards and the weekly challenge: a match created or opened, a finished match seen (`winner`
    /// you|them|draw), a board viewed (`scope` global|friends), the challenge card shown. Never a handle or match id.
    case playH2HCreate
    case playH2HOpen
    case playH2HResult(winner: String)
    case playBoardView(scope: String)
    case playChallengeView
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
    static let alertKinds = ["flight", "hotel", "activity", "trip"]
    static let storyVerdicts = ["great", "good", "typical", "high", "none"]
    static let adviceOutcomes = ["ok", "cached", "error"]
    static let dropVias = ["in_app", "push", "email"]
    static let digestVias = ["in_app", "email_link"]
    static let quickWatchActions = ["add", "undo", "exists", "blocked"]
    static let quickWatchSurfaces = ["results", "chat", "trip", "suggest"]
    static let suggestActions = ["shown", "accepted", "dismissed"]
    static let prefsFields = ["digest", "quiet_hours", "instant", "cap", "group"]
    static let savingsShareTargets = ["native", "copy", "download"]
    static let notifSources = ["push", "inapp"]
    static let feedScopes = ["for_you", "following", "new"]
    static let ideaKinds = ["plan", "recap"]
    static let notifCategories = NotificationCategory.allCases.map(\.rawValue)
    static let socialVisibilities = ["private", "followers", "public"]
    static let socialFollowStates = ["following", "pending", "none"]
    static let socialReportTargets = ["idea", "comment", "profile"]
    static let socialReportReasons = ["spam", "abuse", "sexual", "violence", "misinformation", "other"]
    static let playModes = ["daily", "pack", "challenge", "h2h"]
    static let playWinners = ["you", "them", "draw"]
    static let playBoardScopes = ["global", "friends"]
    static let playPacks = ["flags", "capitals", "landmarks", "cuisine", "none"]
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
        case .alertStoryView(let kind, let verdict):
            name = "alert_story_view"
            if let valid = PropsFilter.enum(kind, allowed: Self.alertKinds) { props["kind"] = .string(valid) }
            if let valid = PropsFilter.enum(verdict, allowed: Self.storyVerdicts) { props["verdict"] = .string(valid) }
        case .alertAdvice(let kind, let outcome):
            name = "alert_advice"
            if let valid = PropsFilter.enum(kind, allowed: Self.alertKinds) { props["kind"] = .string(valid) }
            if let valid = PropsFilter.enum(outcome, allowed: Self.adviceOutcomes) { props["outcome"] = .string(valid) }
        case .alertDropSeen(let kind, let targetHit, let via):
            name = "alert_drop_seen"
            if let valid = PropsFilter.enum(kind, allowed: Self.alertKinds) { props["kind"] = .string(valid) }
            props["target_hit"] = .bool(targetHit)
            if let valid = PropsFilter.enum(via, allowed: Self.dropVias) { props["via"] = .string(valid) }
        case .alertDigestOpen(let via):
            name = "alert_digest_open"
            if let valid = PropsFilter.enum(via, allowed: Self.digestVias) { props["via"] = .string(valid) }
        case .alertQuickWatch(let kind, let action, let surface):
            name = "alert_quick_watch"
            if let valid = PropsFilter.enum(kind, allowed: Self.alertKinds) { props["kind"] = .string(valid) }
            if let valid = PropsFilter.enum(action, allowed: Self.quickWatchActions) { props["action"] = .string(valid) }
            if let valid = PropsFilter.enum(surface, allowed: Self.quickWatchSurfaces) { props["surface"] = .string(valid) }
        case .alertSuggest(let action, let count):
            name = "alert_suggest"
            if let valid = PropsFilter.enum(action, allowed: Self.suggestActions) { props["action"] = .string(valid) }
            int("count", count)
        case .alertPrefsChange(let field):
            name = "alert_prefs_change"
            if let valid = PropsFilter.enum(field, allowed: Self.prefsFields) { props["field"] = .string(valid) }
        case .alertSavingsShare(let target):
            name = "alert_savings_share"
            if let valid = PropsFilter.enum(target, allowed: Self.savingsShareTargets) { props["target"] = .string(valid) }
        case .notifSettingsView:
            name = "notif_settings_view"
        case .notifCategoryToggle(let category, let on):
            name = "notif_category_toggle"
            if let valid = PropsFilter.enum(category, allowed: Self.notifCategories) { props["category"] = .string(valid) }
            props["on"] = .bool(on)
        case .notifQuietHoursChange(let enabled):
            name = "notif_quiet_hours_change"
            props["enabled"] = .bool(enabled)
        case .notifCapChange(let cap):
            name = "notif_cap_change"
            int("cap", cap)
        case .notifOpen(let category, let source):
            name = "notif_open"
            if let valid = PropsFilter.enum(category, allowed: Self.notifCategories) { props["category"] = .string(valid) }
            if let valid = PropsFilter.enum(source, allowed: Self.notifSources) { props["source"] = .string(valid) }
        case .socialFeedView(let scope):
            name = "social_feed_view"
            choice("scope", scope, in: Self.feedScopes)
        case .socialIdeaOpen: name = "social_idea_open"
        case .socialIdeaLike(let on):
            name = "social_idea_like"
            props["on"] = .bool(on)
        case .socialIdeaSave: name = "social_idea_save"
        case .socialIdeaPublish(let kind):
            name = "social_idea_publish"
            choice("kind", kind, in: Self.ideaKinds)
        case .socialComment: name = "social_comment"
        case .socialProfileView: name = "social_profile_view"
        case .socialProfileSave(let visibility):
            name = "social_profile_save"
            choice("visibility", visibility, in: Self.socialVisibilities)
        case .socialFollow(let state):
            name = "social_follow"
            choice("state", state, in: Self.socialFollowStates)
        case .socialBlock(let on):
            name = "social_block"
            props["on"] = .bool(on)
        case .socialReport(let target, let reason):
            name = "social_report"
            choice("target", target, in: Self.socialReportTargets)
            choice("reason", reason, in: Self.socialReportReasons)
        case .playStateView: name = "play_state_view"
        case .playQuizStart(let mode, let pack):
            name = "play_quiz_start"
            choice("mode", mode, in: Self.playModes)
            choice("pack", pack, in: Self.playPacks)
        case .playQuizAnswer(let correct, let elapsedS):
            name = "play_quiz_answer"
            props["correct"] = .bool(correct)
            int("elapsed_s", elapsedS)
        case .playQuizDone(let correct, let mode):
            name = "play_quiz_done"
            int("correct", correct)
            choice("mode", mode, in: Self.playModes)
        case .playH2HCreate: name = "play_h2h_create"
        case .playH2HOpen: name = "play_h2h_open"
        case .playH2HResult(let winner):
            name = "play_h2h_result"
            choice("winner", winner, in: Self.playWinners)
        case .playBoardView(let scope):
            name = "play_board_view"
            choice("scope", scope, in: Self.playBoardScopes)
        case .playChallengeView: name = "play_challenge_view"
        }
        return WireEvent(name: name, props: props)
    }
}
