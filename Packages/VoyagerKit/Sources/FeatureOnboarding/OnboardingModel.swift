import Domain
import Foundation
import Observation
import Telemetry
import UserNotifications
import VoyagerEnv
import VoyagerModel

/// One onboarding step. The raw value is the 0-based index saved in `DeviceSettings.onboardingStep`.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, howYouTravel, homeAndPassport, notifications, firstTrip
}

public enum OnboardingSyncState: Equatable, Sendable {
    case idle, saving, failed
}

/// The state and logic of the 5-step onboarding (UI-free, so it is unit-tested directly).
/// Steps are skippable and resumable: the step and the quiz answers are written to `DeviceSettings` as they change.
@MainActor @Observable
public final class OnboardingModel {
    public let fromSettings: Bool
    /// The steps shown: `fromSettings` leaves out the notifications ask.
    public let steps: [OnboardingStep]
    public private(set) var step: OnboardingStep
    /// 0..<questions.count are the quiz questions, `questions.count` is the traveller-type result.
    public private(set) var quizPage = 0
    public private(set) var answers: [String: [String]]
    public var airportQuery = ""
    public var nationalityQuery = ""
    public private(set) var airportSuggestions: [AirportSuggestion] = []
    public private(set) var nationalitySuggestions: [NationalitySuggestion] = []
    public private(set) var homeAirport: AirportSuggestion?
    public private(set) var passport: NationalitySuggestion?
    public private(set) var syncState: OnboardingSyncState = .idle
    /// Set once the notifications step has been answered (Allow or Not now).
    public private(set) var notificationsAnswered = false

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let track: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let requestNotifications: @MainActor () async -> Bool
    @ObservationIgnored private let onFinish: @MainActor (OnboardingOutcome) -> Void
    @ObservationIgnored private var started = false

    public static let quizQuestions = TravellerQuiz.questions

    /// `track` defaults to the environment's telemetry; `requestNotifications` to the system prompt.
    public init(
        env: AppEnvironment,
        fromSettings: Bool,
        track: (@MainActor (TelemetryEvent) -> Void)? = nil,
        requestNotifications: (@MainActor () async -> Bool)? = nil,
        onFinish: @escaping @MainActor (OnboardingOutcome) -> Void = { _ in }
    ) {
        self.env = env
        self.fromSettings = fromSettings
        self.track = track ?? { [telemetry = env.telemetry] event in telemetry.track(event) }
        self.requestNotifications = requestNotifications ?? {
            (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        }
        self.onFinish = onFinish
        let all = OnboardingStep.allCases.filter { !(fromSettings && $0 == .notifications) }
        steps = all
        answers = env.device.quizAnswers
        if fromSettings {
            step = .welcome
        } else {
            let saved = OnboardingStep(rawValue: env.device.onboardingStep) ?? .welcome
            step = all.contains(saved) ? saved : .welcome
        }
    }

    // MARK: - Derived

    public var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }
    public var stepCount: Int { steps.count }
    public var isLastStep: Bool { step == steps.last }
    public var isOnResult: Bool { step == .howYouTravel && quizPage >= Self.quizQuestions.count }
    public var currentQuestion: QuizQuestion? {
        step == .howYouTravel && quizPage < Self.quizQuestions.count ? Self.quizQuestions[quizPage] : nil
    }

    public var classification: (primary: TravellerType, secondary: [TravellerType]) {
        TravellerClassifier.classify(answers)
    }

    /// The telemetry `step` prop: the 1-based position in the full five-step flow.
    private func telemetryStep(_ step: OnboardingStep) -> Int { step.rawValue + 1 }

    // MARK: - Lifecycle

    /// Call once when the screen appears: emits the first `view`.
    public func start() {
        guard !started else { return }
        started = true
        track(.onboardingStep(step: telemetryStep(step), action: .view))
    }

    /// Loads the saved account preferences so "from settings" shows the current passport. Never fails visibly.
    public func loadExisting() async {
        guard env.auth.session != nil, let current = try? await env.repos.preferences.get() else { return }
        if passport == nil, let nationality = current.nationality, !nationality.isEmpty {
            passport = NationalitySuggestion(nationality: nationality)
        }
    }

    // MARK: - Navigation

    /// Next (or "See my type" on the last question): moves through the quiz pages, then to the next step.
    public func next() {
        if step == .howYouTravel, quizPage < Self.quizQuestions.count {
            quizPage += 1
            return
        }
        track(.onboardingStep(step: telemetryStep(step), action: .next))
        advance()
    }

    /// Skips the current step without answering it.
    public func skip() {
        track(.onboardingStep(step: telemetryStep(step), action: .skip))
        if isLastStep {
            _ = finish()
        } else {
            advance()
        }
    }

    public func back() {
        if step == .howYouTravel, quizPage > 0 {
            quizPage -= 1
            return
        }
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        move(to: steps[index - 1])
    }

    public var canGoBack: Bool {
        (steps.firstIndex(of: step) ?? 0) > 0 || (step == .howYouTravel && quizPage > 0)
    }

    private func advance() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        move(to: steps[index + 1])
    }

    private func move(to next: OnboardingStep) {
        step = next
        quizPage = 0
        if !fromSettings { env.device.onboardingStep = next.rawValue }
        track(.onboardingStep(step: telemetryStep(next), action: .view))
    }

    /// The close button of "from settings": leaves without saving.
    public func close() {
        onFinish(.skipped)
    }

    // MARK: - Quiz

    public func isSelected(_ option: QuizOption, in question: QuizQuestion) -> Bool {
        (answers[question.id] ?? []).contains(option.id)
    }

    /// Single choice replaces the answer (tapping it again clears it); multi choice toggles.
    public func toggle(_ option: QuizOption, in question: QuizQuestion) {
        var chosen = answers[question.id] ?? []
        if let index = chosen.firstIndex(of: option.id) {
            chosen.remove(at: index)
        } else if question.multiChoice {
            chosen.append(option.id)
        } else {
            chosen = [option.id]
        }
        answers[question.id] = chosen.isEmpty ? nil : chosen
        env.device.quizAnswers = answers
    }

    // MARK: - Home airport and passport

    public func refreshAirports() async {
        let query = airportQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            airportSuggestions = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            let found = try await env.repos.reference.airports(query, limit: 6)
            airportSuggestions = found
        } catch {
            if !(error is CancellationError) { airportSuggestions = [] }
        }
    }

    public func refreshNationalities() async {
        let query = nationalityQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            nationalitySuggestions = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            let found = try await env.repos.reference.nationalities(query, limit: 6)
            nationalitySuggestions = found
        } catch {
            if !(error is CancellationError) { nationalitySuggestions = [] }
        }
    }

    public func choose(airport: AirportSuggestion) {
        homeAirport = airport
        airportQuery = ""
        airportSuggestions = []
    }

    public func clearAirport() { homeAirport = nil }

    public func choose(nationality: NationalitySuggestion) {
        passport = nationality
        nationalityQuery = ""
        nationalitySuggestions = []
    }

    public func clearPassport() { passport = nil }

    // MARK: - Notifications

    /// "Allow": the system prompt appears only now. Moves on whatever the answer.
    public func allowNotifications() async {
        let granted = await requestNotifications()
        env.device.reminderOptIn = granted
        notificationsAnswered = true
        track(.onboardingStep(step: telemetryStep(.notifications), action: .next))
        advance()
    }

    /// "Not now": no system prompt.
    public func declineNotifications() {
        env.device.reminderOptIn = false
        notificationsAnswered = true
        skip()
    }

    // MARK: - Finish

    /// "Plan a trip" on the last step: finish, then open Search (prefilled from the saved preferences).
    @discardableResult
    public func finishAndPlan() -> Task<Void, Never> {
        finish(route: .explore(.search))
    }

    /// "Just explore" / "Save changes" / "Finish".
    @discardableResult
    public func finish(route: Route? = nil) -> Task<Void, Never> {
        guard syncState != .saving else { return Task {} }
        track(.onboardingStep(step: telemetryStep(step), action: .done))
        saveLocally()
        pendingRoute = route
        return Task { await sync() }
    }

    @ObservationIgnored private var pendingRoute: Route?

    /// Retry after a failed sync.
    @discardableResult
    public func retrySync() -> Task<Void, Never> {
        guard syncState == .failed else { return Task {} }
        return Task { await sync() }
    }

    /// "Continue without syncing": the local data stays, the account is not updated.
    public func continueWithoutSyncing() {
        complete()
    }

    private func saveLocally() {
        let result = classification
        let types = [result.primary] + result.secondary
        env.device.travellerTypes = types.map(\.rawValue)
        env.device.quizAnswers = answers
        env.device.featureEnabled = Set(FeatureCatalogue.defaults(for: types))
    }

    /// Read-modify-write of `PUT /api/preferences`; no session means nothing to sync.
    func sync() async {
        guard env.auth.session != nil else {
            complete()
            return
        }
        syncState = .saving
        do {
            let current = try await env.repos.preferences.get()
            let merged = try Self.merged(current: current, answers: answers, passport: passport, home: homeAirport)
            _ = try await env.repos.preferences.put(merged)
            complete()
        } catch {
            syncState = .failed
        }
    }

    private func complete() {
        syncState = .idle
        env.device.onboardingCompleted = true
        env.device.onboardingStep = 0
        onFinish(.completed)
        if let route = pendingRoute { env.router.open(route) }
        pendingRoute = nil
    }

    /// The preferences to send: the server's current ones with the quiz patch and the picked passport/home on top.
    static func merged(
        current: Preferences, answers: [String: [String]], passport: NationalitySuggestion?, home: AirportSuggestion?
    ) throws -> Preferences {
        let encoder = JSONEncoder()
        let currentJSON = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(current))
        var object = currentJSON.object ?? [:]
        for (key, value) in TravellerQuiz.preferencesPatch(answers, current: currentJSON).object ?? [:] {
            object[key] = value
        }
        if let nationality = passport?.nationality, !nationality.isEmpty {
            object["nationality"] = .string(nationality)
        }
        if let residence = home?.country ?? home?.city, !residence.isEmpty {
            object["current_residence"] = .string(residence)
        }
        return try JSONDecoder().decode(Preferences.self, from: encoder.encode(JSONValue.object(object)))
    }
}
