import Foundation
import L10n
import Networking
import Observation
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// The AI timing tip (`POST /alerts/watches/flight/{id}/advice`) of one story.
public enum AdviceTipState: Equatable, Sendable {
    case idle
    case loading
    case tip(AdviceTip)
    case failed(String)
}

/// One watch's price story (`GET /alerts/watches/{kind}/{id}/story`): loading, the chart's readout, and the tip.
/// The app never recomputes anything: the verdict, advice code and typical range are the server's; this model only
/// turns them into words.
@MainActor
@Observable
public final class PriceStoryModel {
    public enum Phase: Equatable, Sendable {
        /// Not asked yet.
        case idle
        case loading
        case loaded(PriceStory)
        /// The route is off (an older backend or `alerts_api` < 2): the card shows no story at all.
        case unavailable
        case failed(String)
    }

    public let kind: WatchKind
    public let watchID: Int
    public private(set) var phase: Phase = .idle
    public private(set) var tip: AdviceTipState = .idle
    /// The point the chart readout shows (scrubbing, or the first / latest accessibility action).
    public private(set) var selected: PricePoint?

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var viewTracked = false
    @ObservationIgnored private var loadRun = 0

    public init(
        env: AppEnvironment, kind: WatchKind, watchID: Int, track: @escaping @MainActor (TelemetryEvent) -> Void,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.env = env
        self.kind = kind
        self.watchID = watchID
        self.track = track
        self.now = now
    }

    /// Shows a story without a request (previews and snapshots).
    func show(_ story: PriceStory, tip: AdviceTipState = .idle, selected: PricePoint? = nil) {
        phase = .loaded(story)
        self.tip = tip
        self.selected = selected
    }

    // MARK: Loading

    public var story: PriceStory? {
        if case .loaded(let story) = phase { return story }
        return nil
    }

    /// Loads (or refreshes) the story. A refresh keeps the old story on screen until the new one arrives, and a failed
    /// refresh keeps it too. `alert_story_view` is sent once, with the first story shown.
    public func load() async {
        guard env.alertsV2.isAvailable(.stored) else {
            phase = .unavailable
            return
        }
        loadRun += 1
        let run = loadRun
        if story == nil { phase = .loading }
        do {
            let fetched = try await env.alertsV2.story(kind: kind, id: watchID)
            guard run == loadRun else { return }
            phase = .loaded(fetched)
            if let selected, !fetched.points.contains(selected) { self.selected = nil }
            if !viewTracked {
                viewTracked = true
                track(.alertStoryView(kind: kind.rawValue, verdict: Self.verdict(of: fetched)?.rawValue ?? "none"))
            }
        } catch is CancellationError {
            return
        } catch {
            guard run == loadRun else { return }
            if error is AlertsV2Service.Unavailable {
                phase = .unavailable
            } else if story == nil {
                phase = .failed(Self.loadMessage(error))
            }
        }
    }

    static func loadMessage(_ error: Error) -> String {
        if let api = error as? APIError, case .rateLimited = api, let detail = api.userFacingDetail { return detail }
        return L10n.text(K.priceStory.error.load)
    }

    // MARK: What the card shows

    /// The verdict chip. Hidden when the server sent none, and never shown while live checks are paused (the price may
    /// be stale; the story says "checks paused", never "great price").
    public static func verdict(of story: PriceStory) -> PriceVerdict? {
        if story.advice?.code == .checksPaused { return nil }
        return story.verdict
    }

    public var verdict: PriceVerdict? { story.flatMap(Self.verdict(of:)) }

    public static func verdictText(_ verdict: PriceVerdict) -> String {
        switch verdict {
        case .great: L10n.text(K.priceStory.verdict.great)
        case .good: L10n.text(K.priceStory.verdict.good)
        case .typical: L10n.text(K.priceStory.verdict.typical)
        case .high: L10n.text(K.priceStory.verdict.high)
        }
    }

    /// The advice line for `advice.code` and its `params`. An unknown code shows no line.
    public static func adviceText(_ advice: StoryAdvice?, currency: String?) -> String? {
        guard let advice else { return nil }
        let code = currency ?? "USD"
        switch advice.code {
        case .pending: return L10n.text(K.priceStory.advice.pending)
        case .checksPaused: return L10n.text(K.priceStory.advice.checks_paused, count: advice.days ?? 0)
        case .belowTarget:
            return L10n.text(K.priceStory.advice.below_target, ["by": Fmt.currency(advice.by ?? 0, code: code)])
        case .nearTarget:
            return L10n.text(K.priceStory.advice.near_target, ["gap": Fmt.currency(advice.gap ?? 0, code: code)])
        case .atLowest: return L10n.text(K.priceStory.advice.at_lowest)
        case .belowTypical: return L10n.text(K.priceStory.advice.below_typical)
        case .withinTypical: return L10n.text(K.priceStory.advice.within_typical)
        case .aboveTypical: return L10n.text(K.priceStory.advice.above_typical)
        case .steady: return L10n.text(K.priceStory.advice.steady, count: advice.days ?? 0)
        case .fewChecks: return L10n.text(K.priceStory.advice.few_checks, count: advice.checkCount ?? 0)
        case .unknown: return nil
        }
    }

    /// "Checked today" / "Checked N days ago", from the server's `checked_days_ago`. Nil before the first check.
    public static func checkedText(_ story: PriceStory) -> String? {
        guard !story.pendingFirstCheck, let days = story.checkedDaysAgo else { return nil }
        return days <= 0
            ? L10n.text(K.priceStory.checkedToday) : L10n.text(K.priceStory.checkedAgo, count: days)
    }

    /// An estimate is labelled as one and is never the latest price.
    public static func estimateText(_ story: PriceStory) -> String? {
        guard let estimate = story.estimate else { return nil }
        return L10n.text(K.priceStory.estimate, ["price": Fmt.currency(estimate.price, code: story.currency ?? "USD")])
    }

    // MARK: Chart readout

    /// The newest point on or before `date`'s nearest neighbour: the chart's scrub target.
    public func scrub(to date: Date?) {
        guard let story, let date else { return }
        let plotted = StoryChartData(story: story).points
        guard let nearest = plotted.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
        else { return }
        selected = nearest.point
    }

    public func selectFirst() { selected = story?.points.first }
    public func selectLatest() { selected = story?.points.last }
    public func clearSelection() { selected = nil }

    /// "$412.00 on Nov 9", then how long ago that was.
    public func readout(for point: PricePoint) -> String {
        let currency = story?.currency ?? "USD"
        let price = Fmt.currency(point.price, code: currency)
        guard let date = StoryChartData.parse(point.at) else { return price }
        let line = L10n.text(K.priceStory.chart.point, ["price": price, "date": Fmt.date(date)])
        return "\(line), \(Fmt.relative(date.timeIntervalSince(now())))"
    }

    // MARK: AI timing tip (flights)

    /// Flights with at least one observed price: the other kinds answer `422 advice_unsupported` and a watch with no
    /// price `422 advice_no_data`, so the button is not offered.
    public var canAskForTip: Bool {
        kind == .flight && (story?.hasObservedPrice ?? false) && env.alertsV2.isAvailable(.stored)
    }

    public func requestTip() async {
        guard canAskForTip, tip != .loading else { return }
        tip = .loading
        do {
            let result = try await env.alertsV2.advice(kind: kind, id: watchID)
            tip = .tip(result)
            track(.alertAdvice(kind: kind.rawValue, outcome: result.cached ? "cached" : "ok"))
        } catch is CancellationError {
            tip = .idle
        } catch {
            tip = .failed(Self.adviceMessage(error))
            track(.alertAdvice(kind: kind.rawValue, outcome: "error"))
        }
    }

    /// Every failure of the tip call as words: the AI limit (and billing off, which reads the same to a person), and
    /// one general "could not get a tip" for the rest (`advice_failed`, `advice_unsupported`, `advice_no_data`, a
    /// missing route, the network). A 429 shows the backend's own text.
    public static func adviceMessage(_ error: Error) -> String {
        if let api = error as? APIError {
            if case .rateLimited = api, let detail = api.userFacingDetail { return detail }
            if ["ai_limit", "ai_billing"].contains(errorCode(api)) { return L10n.text(K.priceStory.tip.limit) }
        }
        return L10n.text(K.priceStory.tip.error)
    }
}

/// The envelope's `error_code` of a 4xx or 5xx answer (`{"detail", "error_code"}`), nil for everything else.
func errorCode(_ error: APIError) -> String? {
    switch error {
    case .client(_, _, let code, let body): body["error_code"].string ?? code ?? body["detail"]["error_code"].string
    case .server(_, _, let code): code
    default: nil
    }
}

/// One `PriceStoryModel` per watch, created on first use. The watch cards read it from the environment.
@MainActor
public final class PriceStoryStore {
    private let env: AppEnvironment
    private let track: @MainActor (TelemetryEvent) -> Void
    private let now: @MainActor () -> Date
    private var models: [String: PriceStoryModel] = [:]

    public init(
        env: AppEnvironment, track: @escaping @MainActor (TelemetryEvent) -> Void,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.env = env
        self.track = track
        self.now = now
    }

    public func model(kind: WatchKind, watchID: Int) -> PriceStoryModel {
        let key = "\(kind.rawValue)-\(watchID)"
        if let existing = models[key] { return existing }
        let created = PriceStoryModel(env: env, kind: kind, watchID: watchID, track: track, now: now)
        models[key] = created
        return created
    }
}

private struct PriceStoryStoreKey: EnvironmentKey {
    static var defaultValue: PriceStoryStore? { nil }
}

extension EnvironmentValues {
    /// The story models of the Alerts screen; nil in previews, where a watch card shows no story.
    var priceStories: PriceStoryStore? {
        get { self[PriceStoryStoreKey.self] }
        set { self[PriceStoryStoreKey.self] = newValue }
    }
}
