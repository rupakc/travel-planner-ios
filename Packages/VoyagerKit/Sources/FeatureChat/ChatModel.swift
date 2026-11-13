import Foundation
import L10n
import Observation
import SectionsUI
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// Runs the chat stream of one conversation and publishes the reduced messages. Streamed text is coalesced to
/// at most one UI update per `coalesce` (50 ms). Owned by `ChatRootView` through `@State`.
@MainActor @Observable
final class ChatModel {
    private(set) var messages: [ChatMessageState] = []
    private(set) var isStreaming = false
    private(set) var threadID = UUID()
    /// The `session_context` the server sent last; sent back with the next request.
    private(set) var sessionContext: JSONValue = .object([:])
    var input = ""
    var toast: ToastMessage?
    var safariURL: URL?
    /// How many times `messages` was republished while streaming (tests assert the coalescing).
    @ObservationIgnored private(set) var publishCount = 0

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let coalesce: Duration
    @ObservationIgnored private var turn = ChatTurn()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var lastCommit: ContinuousClock.Instant?
    @ObservationIgnored private var started = false
    private struct Owner { let name: String? }
    /// Whose threads this conversation belongs to; nil until the store has loaded a user.
    @ObservationIgnored private var owner: Owner?

    init(
        env: AppEnvironment, coalesce: Duration = .milliseconds(50),
        track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.coalesce = coalesce
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
    }

    // MARK: - Threads

    /// Follows the signed-in user: when the store now shows another user's threads, this conversation (which
    /// belongs to the previous user) is dropped, so `persist()` can never write it into the new user's file.
    /// Then, once the store has read the current user's file, resumes their latest conversation.
    func syncWithStore() {
        dropForeignConversation()
        let store = env.chatThreads
        guard store.isReady else { return }
        if owner == nil { owner = Owner(name: store.username) }
        resumeLatestIfFresh()
    }

    /// Drops this conversation when it was started for another user than the one the store shows now.
    private func dropForeignConversation() {
        guard let owner, owner.name != env.chatThreads.username else { return }
        self.owner = nil
        stop()
        started = false
        input = ""
        threadID = UUID()
        messages = []
        sessionContext = .object([:])
    }

    /// The most recent stored conversation, when nothing was typed yet and the threads are loaded.
    func resumeLatestIfFresh() {
        guard env.chatThreads.isReady, !started, messages.isEmpty, let latest = env.chatThreads.threads.first else { return }
        open(latest.id)
    }

    func newThread() {
        stop()
        started = true
        threadID = UUID()
        messages = []
        sessionContext = .object([:])
    }

    func open(_ id: UUID) {
        guard let thread = env.chatThreads.thread(id) else { return }
        stop()
        started = true
        threadID = id
        messages = thread.messages.compactMap(ChatMessageState.init(json:))
        sessionContext = thread.sessionContext.object == nil ? .object([:]) : thread.sessionContext
    }

    func deleteThread(_ id: UUID) {
        env.chatThreads.delete(id)
        if id == threadID { newThread() }
    }

    /// The web's "clear": drops this conversation.
    func clear() {
        env.chatThreads.delete(threadID)
        newThread()
    }

    /// Snapshots and tests: shows `messages` as they are, without a stream.
    func load(_ messages: [ChatMessageState]) {
        started = true
        self.messages = messages
    }

    // MARK: - Sending

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        dropForeignConversation()
        // Typed text belongs to the user the store shows now, even before their threads finished loading.
        if owner == nil, env.chatThreads.hasSwitched { owner = Owner(name: env.chatThreads.username) }
        started = true
        input = ""
        messages.append(ChatMessageState(role: .user, content: text))
        let request = ChatRequest(
            messages: ChatHistory.requestMessages(messages),
            selections: env.plan.selections,
            searchResults: env.plan.latestResults,
            sessionContext: sessionContext)
        turn = ChatTurn()
        messages.append(turn.message)
        isStreaming = true
        persist()
        task = Task { [weak self] in await self?.run(request) }
    }

    /// Asks again after a failed reply: the failed assistant message and its question are replaced.
    func retry() {
        guard !isStreaming, messages.count >= 2, let last = messages.last, last.role == .assistant, last.failed,
            messages[messages.count - 2].role == .user
        else { return }
        let question = messages[messages.count - 2].content
        messages.removeLast(2)
        send(question)
    }

    func stop() {
        task?.cancel()
        // `run` finishes the turn; when no stream runs there is nothing to close.
        if task == nil { isStreaming = false }
    }

    private func run(_ request: ChatRequest) async {
        do {
            for try await event in env.repos.chat.stream(request) {
                if Task.isCancelled { break }
                handle(event)
                if turn.finished { break }
            }
        } catch {
            if !Task.isCancelled { fail(error) }
        }
        close(cancelled: Task.isCancelled)
    }

    private func handle(_ event: ChatStreamEvent) {
        let effects = ChatReducer.reduce(&turn, event)
        if let context = turn.sessionContext {
            sessionContext = context
            turn.sessionContext = nil
        }
        for effect in effects { perform(effect) }
        if case .delta = event { publish(force: false) } else { publish(force: true) }
    }

    private func fail(_ error: any Error) {
        let nothingToShow = turn.message.content.isEmpty && turn.message.planning?.itinerary == nil && turn.message.sections.isEmpty
        if nothingToShow {
            if let presentable = error as? any ErrorPresentable {
                turn.message.content = ErrorCopy.message(kind: presentable.presentationKind, detail: presentable.userFacingDetail)
            } else {
                turn.message.content = L10n.text(K.chat.error.generic)
            }
        }
        turn.message.failed = true
    }

    private func close(cancelled: Bool) {
        // Stopped before anything came: no bubble at all, not a "no response" apology.
        if !(cancelled && turn.message.isBlank) { ChatReducer.finish(&turn) }
        flushTask?.cancel()
        flushTask = nil
        if turn.message.isBlank {
            messages.removeAll { $0.id == turn.message.id }
        } else {
            commit()
        }
        isStreaming = false
        task = nil
        persist()
    }

    // MARK: - Publishing

    private func publish(force: Bool) {
        if force {
            flushTask?.cancel()
            flushTask = nil
            commit()
            return
        }
        let now = ContinuousClock.now
        if let last = lastCommit, now - last < coalesce {
            guard flushTask == nil else { return }
            let wait = coalesce - (now - last)
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                self.flushTask = nil
                self.commit()
            }
        } else {
            commit()
        }
    }

    private func commit() {
        lastCommit = ContinuousClock.now
        guard let index = messages.lastIndex(where: { $0.id == turn.message.id }) else { return }
        messages[index] = turn.message
        publishCount += 1
    }

    private func persist() {
        if let owner, owner.name != env.chatThreads.username { return }
        let stored = messages.filter { !$0.isBlank }.map(\.json)
        if stored.isEmpty, env.chatThreads.thread(threadID) == nil { return }
        let context = sessionContext
        let firstUser = messages.first { $0.role == .user }?.content
        env.chatThreads.update(threadID) { thread in
            thread.messages = stored
            thread.sessionContext = context
            if thread.title == nil, let firstUser { thread.title = String(firstUser.prefix(60)) }
        }
    }

    // MARK: - Effects

    private func perform(_ effect: ChatEffect) {
        switch effect {
        case .planAction(let action, let field, let data):
            env.plan.apply(planAction: (action: action, field: field, data: data))
        case .openImport(let url):
            guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased()) else { return }
            env.router.open(.importLink(parsed))
        case .planningStarted:
            track(ChatTelemetry.searchSubmit(context: sessionContext))
        case .tripMapped(let map):
            if let data = ChatTelemetry.searchData(tripMap: map) { env.plan.searchData = data }
        case .sectionData(let section, let data):
            var results = env.plan.latestResults.object ?? [:]
            results[section] = data
            env.plan.latestResults = .object(results)
        }
    }

    // MARK: - Hosting sections

    func makeContext(layout: LayoutClass) -> SectionContext {
        SectionContext(
            isSelected: { [env] field, item in env.plan.contains(field: field, item: item) },
            toggle: { [weak self] field, item in self?.toggle(field: field, item: item) },
            watch: { [weak self] request in self?.watch(request) },
            openURL: { [weak self] url, section in self?.open(url, section: section) },
            showsVerification: false,
            searchData: env.plan.searchData,
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

    func openImport(_ url: String) {
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased()) else { return }
        env.router.open(.importLink(parsed))
    }

    private func watch(_ request: WatchRequest) {
        Task { [weak self] in
            guard let self else { return }
            let result = await env.watches.handle(request)
            toast = ToastMessage(Self.watchText(result, kind: request.kind))
        }
    }

    static func watchText(_ result: WatchCreateResult, kind: WatchKind) -> String {
        let flight = kind == .flight
        switch result {
        case .created:
            return L10n.text(flight ? K.alerts.dialog.fare.watching : priceWatching(kind))
        case .alreadyWatching:
            return L10n.text(flight ? K.alerts.dialog.fare.already : priceAlready(kind))
        case .noLivePrice(let message):
            return message
        case .failed:
            return L10n.text(flight ? K.alerts.dialog.fare.startFailed : priceFailed(kind))
        }
    }

    private static func priceWatching(_ kind: WatchKind) -> LKey {
        switch kind {
        case .hotel: K.alerts.dialog.price.watching.hotel
        case .activity: K.alerts.dialog.price.watching.activity
        default: K.alerts.dialog.price.watching.trip
        }
    }

    private static func priceAlready(_ kind: WatchKind) -> LKey {
        switch kind {
        case .hotel: K.alerts.dialog.price.already.hotel
        case .activity: K.alerts.dialog.price.already.activity
        default: K.alerts.dialog.price.already.trip
        }
    }

    private static func priceFailed(_ kind: WatchKind) -> LKey {
        switch kind {
        case .hotel: K.alerts.dialog.price.failed.hotel
        case .activity: K.alerts.dialog.price.failed.activity
        default: K.alerts.dialog.price.failed.trip
        }
    }
}

/// Telemetry and plan-store facts derived from chat data. Counts and booleans only: no text leaves the device.
enum ChatTelemetry {
    static func searchSubmit(context: JSONValue) -> TelemetryEvent {
        let travelers = max(1, min(context["num_travelers"].int ?? 1, 99))
        let destinations = context["destinations"].array?.count ?? 0
        return .searchSubmit(
            mode: .chat, travelers: travelers, nights: nights(context["departure_date"].string, context["return_date"].string),
            multiCity: destinations > 1)
    }

    static func nights(_ from: String?, _ to: String?) -> Int {
        guard let from, let to, let start = date(from), let end = date(to) else { return 0 }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, min(days, 365))
    }

    private static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    /// The `search_data` a chat plan saves with: the trip map's origin, first city, dates and travellers.
    static func searchData(tripMap map: JSONValue) -> JSONValue? {
        var object: [String: JSONValue] = [:]
        if let origin = map["origin"].string { object["origin"] = .string(origin) }
        let cities = (map["cities"].array ?? []).compactMap { $0["city"].string }
        if let first = cities.first { object["destination"] = .string(first) }
        if cities.count > 1 { object["destinations"] = .array(cities.map(JSONValue.string)) }
        if let departure = map["departure_date"].string { object["departure_date"] = .string(departure) }
        if let back = map["return_date"].string { object["return_date"] = .string(back) }
        if let travelers = map["num_travelers"].int { object["num_travelers"] = .number(Double(travelers)) }
        return object.isEmpty ? nil : .object(object)
    }
}
