import Foundation
import L10n
import Networking
import Observation
import SectionsUI
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// Runs one search stream and publishes the reduced state. Owned by `ResultsView` through `@State` (created once
/// per request), so a size-class change keeps the stream. A stream that ends without `done`, or throws a network
/// error, is retried once and replays into the sections already shown; a second break sets `interrupted`.
@MainActor @Observable
public final class ResultsModel {
    public private(set) var state: ResultsState
    /// The stream broke twice: the sections shown are what arrived (the web's "interrupted" warning).
    public private(set) var interrupted = false
    /// The stream failed with something a retry does not fix (rate limit, sign-in, server): the copy to show.
    public private(set) var failureMessage: String?
    /// A pending non-blocking message (watch result); the view binds a toast to it.
    public var toast: ToastMessage?
    /// A provider page to open in `SFSafariViewController`.
    public var safariURL: URL?
    public let request: TravelSearchRequest

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var sentFirstByte = false
    @ObservationIgnored private var sentFirstSection = false
    @ObservationIgnored private var sentComplete = false
    @ObservationIgnored private var sentAbandon = false
    @ObservationIgnored private var frozen = false

    /// `track` and `announce` default to the environment's telemetry and VoiceOver; tests record them.
    public init(
        env: AppEnvironment, request: TravelSearchRequest,
        track: (@MainActor (TelemetryEvent) -> Void)? = nil,
        announce: (@MainActor (String) -> Void)? = nil
    ) {
        self.env = env
        self.request = request
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
        self.announce = announce ?? { LiveRegion.announce($0) }
        state = ResultsState(searchData: Self.searchData(for: request))
    }

    /// The request as the plan store and the itinerary fallback read it (`departure_date`, `destination`, ...).
    static func searchData(for request: TravelSearchRequest) -> JSONValue {
        guard let data = try? JSONEncoder().encode(request),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return .object([:]) }
        return value
    }

    /// Snapshots: shows `state` as it is and never streams.
    func freeze(_ state: ResultsState) {
        self.state = state
        frozen = true
    }

    // MARK: - Lifecycle

    /// Starts the stream (once; a later call while it runs, or after it finished, does nothing).
    public func start() {
        guard task == nil, !state.done, !frozen else { return }
        if startedAt == nil {
            startedAt = Date()
            env.plan.latestResults = .object([:])
            if env.plan.searchData != state.searchData { env.plan.searchData = state.searchData }
        }
        task = Task { [weak self] in await self?.run() }
    }

    /// The view went away: stops the stream and, if it had not finished, reports the abandon (once).
    public func cancel() {
        task?.cancel()
        task = nil
        guard startedAt != nil, !state.done, !sentAbandon else { return }
        sentAbandon = true
        track(.searchAbandon(ms: elapsedMS, sections: state.readyCount))
    }

    // MARK: - Stream

    private enum Outcome: Sendable {
        case finished, cancelled, endedEarly
        case threw(any Error)
    }

    private func run() async {
        var breaks = 0
        while !Task.isCancelled {
            let stream = env.repos.search.stream(request)
            let outcome = await Self.consume(stream, from: state) { [weak self] next, event in
                self?.publish(next, event)
            }
            switch outcome {
            case .finished, .cancelled:
                task = nil
                return
            case .endedEarly:
                breaks += 1
            case .threw(let error):
                if let api = error as? APIError {
                    switch api {
                    case .cancelled:
                        task = nil
                        return
                    case .network, .interrupted:
                        breaks += 1
                    default:
                        fail(api)
                        return
                    }
                } else if error is CancellationError {
                    task = nil
                    return
                } else {
                    breaks += 1
                }
            }
            if breaks > 1 {
                settleAfterBreak()
                return
            }
        }
    }

    /// Reduces off the main actor and hands each state to `publish` on it.
    nonisolated private static func consume(
        _ stream: AsyncThrowingStream<SearchStreamEvent, Error>,
        from initial: ResultsState,
        publish: @MainActor @Sendable (ResultsState, SearchStreamEvent) -> Void
    ) async -> Outcome {
        var current = initial
        do {
            for try await event in stream {
                current = ResultsReducer.reduce(current, event)
                await publish(current, event)
                if case .done = event { return .finished }
            }
            return Task.isCancelled ? .cancelled : .endedEarly
        } catch {
            return Task.isCancelled ? .cancelled : .threw(error)
        }
    }

    private func publish(_ next: ResultsState, _ event: SearchStreamEvent) {
        let previous = state
        state = next
        if !sentFirstByte {
            sentFirstByte = true
            track(.perf(metric: .ttfb, value: Double(elapsedMS), route: "/results"))
        }
        switch event {
        case .section(let type, _, _):
            if !sentFirstSection, SectionID(rawValue: type) != nil {
                sentFirstSection = true
                track(.searchFirstSection(ms: elapsedMS))
            }
            announceFinished(type: type, previous: previous, next: next)
            env.plan.latestResults = next.latestResults
        case .done:
            env.plan.latestResults = next.latestResults
            if !sentComplete {
                sentComplete = true
                track(.searchComplete(ms: elapsedMS, sections: next.readyCount, errors: next.errorCount))
            }
        case .agentStatus, .unknown:
            break
        }
    }

    private func announceFinished(type: String, previous: ResultsState, next: ResultsState) {
        guard let id = SectionID(rawValue: type), next.status(id) == .done, previous.status(id) != .done,
            next.sections[id]?.hasGoodData == true
        else { return }
        announce("\(id.title): \(L10n.text(K.sections.page.done))")
    }

    /// Both attempts broke: keep what arrived, finish the rest (the web's `finalize()`), show the interrupted copy.
    private func settleAfterBreak() {
        task = nil
        interrupted = true
        state = ResultsReducer.reduce(state, .done)
        env.plan.latestResults = state.latestResults
    }

    private func fail(_ error: any ErrorPresentable) {
        task = nil
        failureMessage = ErrorCopy.message(kind: error.presentationKind, detail: error.userFacingDetail)
        state = ResultsReducer.reduce(state, .done)
        env.plan.latestResults = state.latestResults
    }

    private var elapsedMS: Int {
        Int((Date().timeIntervalSince(startedAt ?? Date()) * 1000).rounded())
    }

    // MARK: - Hosting sections

    /// What a section needs from this screen: the plan store, the watch coordinator and Safari.
    public func makeContext(layout: LayoutClass) -> SectionContext {
        SectionContext(
            isSelected: { [env] field, item in env.plan.contains(field: field, item: item) },
            toggle: { [weak self] field, item in self?.toggle(field: field, item: item) },
            watch: { [weak self] request in self?.watch(request) },
            openURL: { [weak self] url, section in self?.open(url, section: section) },
            showsVerification: true,
            searchData: env.plan.searchData ?? state.searchData,
            layout: layout)
    }

    func toggle(field: String, item: JSONValue) {
        env.plan.toggle(field: field, item: item)
        if env.plan.contains(field: field, item: item) { track(.planSelect(section: field)) }
    }

    func open(_ url: URL, section: String) {
        guard BookingLink.isAllowed(url), let domain = BookingLink.domain(of: url) else { return }
        track(.linkOut(section: section, domain: domain))
        safariURL = url
    }

    func watch(_ request: WatchRequest) {
        Task { [weak self] in
            guard let self else { return }
            let result = await env.watches.handle(request)
            toast = ToastMessage(Self.watchText(result, kind: request.kind))
        }
    }

    static func watchText(_ result: WatchCreateResult, kind: WatchKind) -> String {
        switch result {
        case .created:
            return L10n.text(kind == .flight ? K.alerts.dialog.fare.watching : watching(kind))
        case .alreadyWatching:
            return L10n.text(kind == .flight ? K.alerts.dialog.fare.already : already(kind))
        case .noLivePrice(let message):
            return message
        case .failed:
            return L10n.text(kind == .flight ? K.alerts.dialog.fare.startFailed : failed(kind))
        }
    }

    private static func watching(_ kind: WatchKind) -> LKey {
        switch kind {
        case .hotel: K.alerts.dialog.price.watching.hotel
        case .activity: K.alerts.dialog.price.watching.activity
        default: K.alerts.dialog.price.watching.trip
        }
    }

    private static func already(_ kind: WatchKind) -> LKey {
        switch kind {
        case .hotel: K.alerts.dialog.price.already.hotel
        case .activity: K.alerts.dialog.price.already.activity
        default: K.alerts.dialog.price.already.trip
        }
    }

    private static func failed(_ kind: WatchKind) -> LKey {
        switch kind {
        case .hotel: K.alerts.dialog.price.failed.hotel
        case .activity: K.alerts.dialog.price.failed.activity
        default: K.alerts.dialog.price.failed.trip
        }
    }
}
