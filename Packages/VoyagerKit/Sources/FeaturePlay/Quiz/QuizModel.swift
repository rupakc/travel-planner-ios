import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// One quiz run: load (or resume) a session, show a question, send the choice, show what the server answered, move on,
/// then the summary. The server checks and times every answer and decides every point total; the 15 second countdown is
/// for feel only and never stops an answer (plan R14).
@MainActor @Observable
final class QuizModel {
    enum Phase: Equatable {
        case loading
        case question
        case summary
        case unavailable
        case failed(message: String, retryable: Bool)
    }

    /// Seconds a question shows on its countdown.
    static let questionSeconds = 15

    private(set) var phase: Phase = .loading
    private(set) var session: QuizSession?
    /// Position in `session.questions`.
    private(set) var position = 0
    private(set) var selected: String?
    private(set) var result: AnswerResult?
    private(set) var busy = false
    private(set) var secondsLeft = QuizModel.questionSeconds
    /// A failed answer's text; the same question stays open for another try.
    private(set) var errorText: String?
    private(set) var summary: QuizSummary?

    let sessionID: String
    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private(set) var timerTask: Task<Void, Never>?
    /// What the server said about each answer given in this run (for the fallback summary only).
    @ObservationIgnored private var answered: [Int: AnswerResult] = [:]
    /// The summary that came with the last answer, shown after "See result".
    @ObservationIgnored private var finished: QuizSummary?

    init(
        env: AppEnvironment, sessionID: String,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.sessionID = sessionID
        self.sleep = sleep
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    var questions: [PlayQuestion] { session?.questions ?? [] }
    var question: PlayQuestion? { questions.indices.contains(position) ? questions[position] : nil }
    var isLast: Bool { position >= questions.count - 1 }
    var progressText: String {
        L10n.text(K.play.quiz.progress, ["current": String(position + 1), "total": String(max(questions.count, 1))])
    }

    var timerText: String { L10n.text(K.play.quiz.timer, count: secondsLeft) }

    /// The XP of the finished quiz, only when the server reported some.
    var xpEarned: Int { summary?.xp?.awardedPoints ?? 0 }

    /// "Share result": a finished session on a server with Sharing 2.0 (R15). The card is the pack and the score, never
    /// time or answers, and the sharer's name stays hidden (the quiz kind has no options).
    var canShare: Bool { phase == .summary && summary != nil && env.play.isAvailable && env.shares.isAvailable }

    /// Opens the share sheet for this session through the router.
    func share() {
        guard canShare else { return }
        env.router.open(.shareSheet(.quiz(sessionID: sessionID)))
    }

    func load() async {
        guard env.play.isAvailable else {
            phase = .unavailable
            return
        }
        phase = .loading
        do {
            let loaded = try await env.play.call { try await $0.session(id: sessionID) }
            guard !Task.isCancelled else { return }
            session = loaded
            if loaded.done || loaded.firstUnanswered == nil {
                summary = loaded.summary ?? derivedSummary(of: loaded)
                phase = .summary
            } else if let next = loaded.firstUnanswered {
                position = loaded.questions.firstIndex(of: next) ?? 0
                openQuestion()
            }
        } catch is CancellationError {
            return
        } catch {
            fail(error)
        }
    }

    /// A finished session without a `summary`: only the server's own per-answer numbers, added up for display.
    private func derivedSummary(of session: QuizSession) -> QuizSummary {
        var points = session.answers.compactMap(\.points).reduce(0, +)
        var correct = session.answers.filter { $0.correct == true }.count
        let given = Set(session.answers.map(\.index))
        for (index, answer) in answered where !given.contains(index) {
            points += answer.points
            if answer.correct { correct += 1 }
        }
        return QuizSummary(score: points, correct: correct, total: session.questions.count)
    }

    private func fail(_ error: any Error) {
        timerTask?.cancel()
        if error is PlayService.Unavailable {
            phase = .unavailable
            return
        }
        let retryable = (error as? APIError).flatMap(PlayFailure.from) == nil
        phase = .failed(message: PlayMessage.text(for: error), retryable: retryable)
    }

    private func openQuestion() {
        selected = nil
        result = nil
        errorText = nil
        phase = .question
        startTimer()
    }

    private func startTimer() {
        timerTask?.cancel()
        secondsLeft = Self.questionSeconds
        let wait = sleep
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                if (self?.secondsLeft ?? 0) <= 0 { return }
                do { try await wait(.seconds(1)) } catch { return }
                self?.secondsLeft -= 1
            }
        }
    }

    func stopTimer() {
        timerTask?.cancel()
    }

    /// Sends the choice. A question this build cannot render is never answered.
    func pick(_ option: PlayOption) async {
        guard let question, question.isSupported, !busy, result == nil else { return }
        busy = true
        errorText = nil
        selected = option.id
        defer { busy = false }
        do {
            let index = question.index
            let answer = try await env.play.call { try await $0.answer(sessionID: sessionID, index: index, choice: option.id) }
            timerTask?.cancel()
            answered[index] = answer
            // After the last answer the summary comes first: `next()` (the "See result" button) needs it, and the
            // button only appears once `result` is set.
            if answer.done {
                if let summary = answer.summary {
                    finished = summary
                } else {
                    finished = await fetchSummary()
                }
            }
            result = answer
            emit(.playQuizAnswer(correct: answer.correct, elapsedS: max(0, Int((Double(answer.elapsedMs ?? 0) / 1000).rounded()))))
        } catch is CancellationError {
            selected = nil
        } catch {
            selected = nil
            let failure = (error as? APIError).flatMap(PlayFailure.from)
            if failure == .sessionExpired || failure == .sessionNotFound || error is PlayService.Unavailable {
                fail(error)
            } else {
                errorText = PlayMessage.text(for: error)
            }
        }
    }

    private func fetchSummary() async -> QuizSummary {
        let loaded = try? await env.play.call { try await $0.session(id: sessionID) }
        if let summary = loaded?.summary { return summary }
        return derivedSummary(of: loaded ?? session ?? QuizSession(sessionID: sessionID))
    }

    /// "Next question" or, after the last answer, "See result".
    func next() {
        guard let result else { return }
        if result.done, let done = finished {
            summary = done
            phase = .summary
            emit(.playQuizDone(correct: done.correct, mode: session?.mode ?? ""))
            return
        }
        guard !result.done else { return }
        position += 1
        openQuestion()
    }
}
