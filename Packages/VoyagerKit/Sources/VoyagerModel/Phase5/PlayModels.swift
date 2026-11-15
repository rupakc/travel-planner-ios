import Foundation

// Play (`docs/Social-API.md`): daily quiz and packs, head-to-head, weekly boards and the weekly challenge. The server
// checks and times every answer and decides every point total, streak and XP; the app only sends the choice and shows
// what comes back (plan rulings R14, "server decides"). Unknown enum values, question kinds and keys degrade, never crash.

// MARK: State

/// `daily.streak`. `freeze_available`: one freeze a week, never punishing.
public struct QuizStreak: Sendable, Hashable {
    public var current: Int
    public var longest: Int
    public var freezeAvailable: Bool

    public init(current: Int = 0, longest: Int = 0, freezeAvailable: Bool = false) {
        self.current = current
        self.longest = longest
        self.freezeAvailable = freezeAvailable
    }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        self.init(
            current: json["current"].lenientInt ?? 0, longest: json["longest"].lenientInt ?? 0,
            freezeAvailable: json["freeze_available"].lenientBool ?? false)
    }
}

public struct DailyQuizState: Sendable, Hashable {
    public var available: Bool
    public var done: Bool
    /// The score of a finished daily; nil while it is not done.
    public var score: Int?
    public var streak: QuizStreak

    public init(available: Bool = false, done: Bool = false, score: Int? = nil, streak: QuizStreak = QuizStreak()) {
        self.available = available
        self.done = done
        self.score = score
        self.streak = streak
    }

    init(json: JSONValue) {
        self.init(
            available: json["available"].lenientBool ?? false, done: json["done"].lenientBool ?? false,
            score: json["score"].lenientInt, streak: QuizStreak(json: json["streak"]) ?? QuizStreak())
    }
}

/// One quiz pack. The four known ids are `flags`, `capitals`, `landmarks`, `cuisine`; a new one is shown by its title key.
public struct QuizPack: JSONBacked, Sendable, Hashable, Identifiable {
    public var id: String
    /// A `play` catalogue key suffix; an unknown one falls back to the id.
    public var titleKey: String?
    /// The size of the pack's question pool.
    public var questions: Int

    public init(id: String, titleKey: String? = nil, questions: Int = 0) {
        self.id = id
        self.titleKey = titleKey
        self.questions = questions
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let id = json["id"].string, !id.isEmpty else { return nil }
        self.init(id: id, titleKey: json["title_key"].string, questions: json["questions"].lenientInt ?? 0)
    }
}

/// The weekly challenge ("Know before you go"). `kind` is `destination` (the next trip's country) or `featured`.
public struct PlayChallenge: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case destination, featured
        case unknown(String)
    }

    public var id: String
    public var kind: Kind
    public var country: String?
    public var titleKey: String?
    public var done: Bool

    public init(id: String, kind: Kind = .featured, country: String? = nil, titleKey: String? = nil, done: Bool = false) {
        self.id = id
        self.kind = kind
        self.country = country
        self.titleKey = titleKey
        self.done = done
    }

    init?(json: JSONValue) {
        guard let id = json["id"].string, !id.isEmpty else { return nil }
        let kind: Kind =
            switch json["kind"].string {
            case "destination": .destination
            case "featured": .featured
            case .some(let other): .unknown(other)
            case nil: .featured
            }
        self.init(
            id: id, kind: kind, country: json["country"].string, titleKey: json["title_key"].string,
            done: json["done"].lenientBool ?? false)
    }
}

extension PlayChallenge: JSONBacked {
    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }
}

/// `GET /play/state`.
public struct PlayState: JSONBacked, Sendable, Hashable {
    public var daily: DailyQuizState
    public var packs: [QuizPack]
    public var challenge: PlayChallenge?
    /// Head-to-head matches waiting for the caller.
    public var openH2H: Int

    public init(
        daily: DailyQuizState = DailyQuizState(), packs: [QuizPack] = [], challenge: PlayChallenge? = nil, openH2H: Int = 0
    ) {
        self.daily = daily
        self.packs = packs
        self.challenge = challenge
        self.openH2H = openH2H
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        self.init(
            daily: DailyQuizState(json: json["daily"]), packs: json["packs"].models(QuizPack.self),
            challenge: PlayChallenge(json: json["challenge"]), openH2H: json["open_h2h"].lenientInt ?? 0)
    }
}

// MARK: Quiz

public enum QuizMode: String, Sendable, Hashable {
    case daily, pack, challenge
}

/// `POST /play/quiz`. `pack` is only for `pack` mode.
public struct QuizStart: Encodable, Sendable, Hashable {
    public var mode: QuizMode
    public var pack: String?
    public var locale: String?

    public init(mode: QuizMode, pack: String? = nil, locale: String? = nil) {
        self.mode = mode
        self.pack = pack
        self.locale = locale
    }

    enum CodingKeys: String, CodingKey {
        case mode, pack, locale
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode.rawValue, forKey: .mode)
        try container.encodeIfPresent(mode == .pack ? pack : nil, forKey: .pack)
        try container.encodeIfPresent(locale, forKey: .locale)
    }
}

/// The copy a question prompt uses (`prompt.template`). An unknown one makes the question unsupported.
public enum PromptTemplate: Sendable, Hashable {
    case flag, capitalOf, countryOfCapital, landmarkCountry, dishCountry
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "flag": self = .flag
        case "capital_of": self = .capitalOf
        case "country_of_capital": self = .countryOfCapital
        case "landmark_country": self = .landmarkCountry
        case "dish_country": self = .dishCountry
        default: self = .unknown(rawValue)
        }
    }

    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }
}

public struct PlayOption: Sendable, Hashable, Identifiable {
    /// Opaque (`a` to `d`), shuffled per session.
    public var id: String
    public var label: String
    /// ISO alpha-2, only on country-labelled options, so the name can be shown in the app's language.
    public var code: String?

    public init(id: String, label: String, code: String? = nil) {
        self.id = id
        self.label = label
        self.code = code
    }
}

public struct PlayQuestion: Sendable, Hashable, Identifiable {
    public var index: Int
    /// The server's `kind` text, kept as sent.
    public var kind: String
    public var template: PromptTemplate
    /// The prompt's placeholder values (`country`, `capital`, `landmark`, `dish`, `code`, ...), read by the views.
    public var prompt: JSONValue
    public var options: [PlayOption]

    public var id: Int { index }

    public init(index: Int, kind: String = "", template: PromptTemplate, prompt: JSONValue = .null, options: [PlayOption]) {
        self.index = index
        self.kind = kind
        self.template = template
        self.prompt = prompt
        self.options = options
    }

    init?(json: JSONValue) {
        guard let index = json["index"].lenientInt else { return nil }
        let options = (json["options"].array ?? []).compactMap { item -> PlayOption? in
            guard let id = item["id"].lenientString, !id.isEmpty else { return nil }
            return PlayOption(id: id, label: item["label"].string ?? "", code: item["code"].string)
        }
        self.init(
            index: index, kind: json["kind"].string ?? "", template: PromptTemplate(rawValue: json["prompt"]["template"].string ?? ""),
            prompt: json["prompt"], options: options)
    }

    /// A question of a kind this app version cannot render: it shows "update the app" and is skipped, never a crash.
    public var isSupported: Bool { template.isKnown && options.count >= 2 }
}

extension PlayQuestion: JSONBacked {
    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }
}

/// An answer already given (`answers` of a resumed session). The contract does not spell the element out; `index` is
/// the only key required, the rest is read when present.
public struct GivenAnswer: JSONBacked, Sendable, Hashable {
    public var index: Int
    public var choice: String?
    public var correct: Bool?
    public var correctChoice: String?
    public var points: Int?

    public init(index: Int, choice: String? = nil, correct: Bool? = nil, correctChoice: String? = nil, points: Int? = nil) {
        self.index = index
        self.choice = choice
        self.correct = correct
        self.correctChoice = correctChoice
        self.points = points
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let index = json["index"].lenientInt else { return nil }
        self.init(
            index: index, choice: json["choice"].lenientString, correct: json["correct"].lenientBool,
            correctChoice: json["correct_choice"].lenientString, points: json["points"].lenientInt)
    }
}

/// `summary` of a finished session. `xp` is the server's `GameDelta` (absent or hidden when the game is off).
public struct QuizSummary: Sendable, Hashable {
    public var score: Int
    public var correct: Int
    public var total: Int
    public var xp: GameDelta?
    public var streak: QuizStreak?

    public init(score: Int, correct: Int, total: Int, xp: GameDelta? = nil, streak: QuizStreak? = nil) {
        self.score = score
        self.correct = correct
        self.total = total
        self.xp = xp
        self.streak = streak
    }

    init?(json: JSONValue) {
        guard json.object != nil, let score = json["score"].lenientInt else { return nil }
        self.init(
            score: score, correct: json["correct"].lenientInt ?? 0, total: json["total"].lenientInt ?? 5,
            xp: GameDelta(json: json["xp"]), streak: QuizStreak(json: json["streak"]))
    }
}

/// A quiz session as `POST /play/quiz`, `GET /play/quiz/{id}` and the head-to-head create and accept answer it. For a
/// head-to-head, `matchID` is the match id (`id`) and the session is an ordinary one of mode `h2h`.
public struct QuizSession: JSONBacked, Sendable, Hashable {
    public var sessionID: String
    public var matchID: String?
    /// `daily`, `pack`, `challenge` or `h2h` (kept as sent).
    public var mode: String
    public var pack: String?
    public var questions: [PlayQuestion]
    public var expiresAt: String?
    public var answers: [GivenAnswer]
    public var done: Bool
    public var resumed: Bool
    public var summary: QuizSummary?

    public init(
        sessionID: String, matchID: String? = nil, mode: String = "daily", pack: String? = nil, questions: [PlayQuestion] = [],
        expiresAt: String? = nil, answers: [GivenAnswer] = [], done: Bool = false, resumed: Bool = false, summary: QuizSummary? = nil
    ) {
        self.sessionID = sessionID
        self.matchID = matchID
        self.mode = mode
        self.pack = pack
        self.questions = questions
        self.expiresAt = expiresAt
        self.answers = answers
        self.done = done
        self.resumed = resumed
        self.summary = summary
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let sessionID = json["session_id"].lenientString, !sessionID.isEmpty else { return nil }
        self.init(
            sessionID: sessionID, matchID: json["id"].lenientString, mode: json["mode"].string ?? "daily", pack: json["pack"].string,
            questions: json["questions"].models(PlayQuestion.self).sorted { $0.index < $1.index }, expiresAt: json["expires_at"].string,
            answers: json["answers"].models(GivenAnswer.self), done: json["done"].lenientBool ?? false,
            resumed: json["resumed"].lenientBool ?? false, summary: QuizSummary(json: json["summary"]))
    }

    /// The question to show on resume: the first one without an answer, or nil when every question was answered.
    public var firstUnanswered: PlayQuestion? {
        let answered = Set(answers.map(\.index))
        return questions.first { !answered.contains($0.index) }
    }
}

/// `POST /play/quiz/{id}/answer`.
public struct AnswerResult: JSONBacked, Sendable, Hashable {
    public var correct: Bool
    public var correctChoice: String
    /// The server's points (100 for correct plus up to 50 for speed); the app never computes them.
    public var points: Int
    public var elapsedMs: Int?
    public var done: Bool
    public var summary: QuizSummary?

    public init(
        correct: Bool, correctChoice: String, points: Int, elapsedMs: Int? = nil, done: Bool = false, summary: QuizSummary? = nil
    ) {
        self.correct = correct
        self.correctChoice = correctChoice
        self.points = points
        self.elapsedMs = elapsedMs
        self.done = done
        self.summary = summary
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let correct = json["correct"].lenientBool, let choice = json["correct_choice"].lenientString else { return nil }
        self.init(
            correct: correct, correctChoice: choice, points: json["points"].lenientInt ?? 0, elapsedMs: json["elapsed_ms"].lenientInt,
            done: json["done"].lenientBool ?? false, summary: QuizSummary(json: json["summary"]))
    }
}

/// One finished session of `GET /play/history`.
public struct QuizHistoryEntry: JSONBacked, Sendable, Hashable, Identifiable {
    public var sessionID: String
    public var mode: String
    public var pack: String?
    public var score: Int
    public var correct: Int
    public var finishedAt: String?

    public var id: String { sessionID }

    public init(sessionID: String, mode: String, pack: String? = nil, score: Int, correct: Int, finishedAt: String? = nil) {
        self.sessionID = sessionID
        self.mode = mode
        self.pack = pack
        self.score = score
        self.correct = correct
        self.finishedAt = finishedAt
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let sessionID = json["session_id"].lenientString, !sessionID.isEmpty else { return nil }
        self.init(
            sessionID: sessionID, mode: json["mode"].string ?? "", pack: json["pack"].string, score: json["score"].lenientInt ?? 0,
            correct: json["correct"].lenientInt ?? 0, finishedAt: json["finished_at"].string)
    }
}

public struct QuizHistory: JSONBacked, Sendable, Hashable {
    public var entries: [QuizHistoryEntry]

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    /// The contract names the entries but not the wrapper: accept a bare array or `{"history"|"sessions"|"entries": [...]}`.
    init?(json: JSONValue) {
        if json.array != nil {
            entries = json.models(QuizHistoryEntry.self)
        } else if json.object != nil {
            let list = ["history", "sessions", "entries", "items"].map { json[$0] }.first { $0.array != nil } ?? .null
            entries = list.models(QuizHistoryEntry.self)
        } else {
            return nil
        }
    }
}

// MARK: Head-to-head

/// The caller's view of a match. An unknown state is shown as a plain "waiting" row without actions.
public enum H2HState: Sendable, Hashable {
    case waitingYou, waitingThem, done, declined, expired
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "waiting_you": self = .waitingYou
        case "waiting_them": self = .waitingThem
        case "done": self = .done
        case "declined": self = .declined
        case "expired": self = .expired
        default: self = .unknown(rawValue)
        }
    }
}

public enum H2HWinner: String, Sendable, Hashable {
    case you, them, draw
}

public struct H2HMatch: JSONBacked, Sendable, Hashable, Identifiable {
    public var id: String
    public var opponent: String
    public var pack: String?
    public var state: H2HState
    public var you: Int?
    /// nil until both players are done (the opponent's score is never shown earlier).
    public var them: Int?
    public var winner: H2HWinner?
    public var expiresAt: String?
    /// The caller's own session for this match.
    public var sessionID: String?

    public init(
        id: String, opponent: String, pack: String? = nil, state: H2HState, you: Int? = nil, them: Int? = nil,
        winner: H2HWinner? = nil, expiresAt: String? = nil, sessionID: String? = nil
    ) {
        self.id = id
        self.opponent = opponent
        self.pack = pack
        self.state = state
        self.you = you
        self.them = them
        self.winner = winner
        self.expiresAt = expiresAt
        self.sessionID = sessionID
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard let id = json["id"].lenientString, !id.isEmpty, let opponent = json["opponent"]["handle"].string else { return nil }
        let state = H2HState(rawValue: json["state"].string ?? "")
        let finished = state == .done
        self.init(
            id: id, opponent: opponent, pack: json["pack"].string, state: state, you: json["you"].lenientInt,
            // Defensive: the opponent's score and the winner count only once the match is done.
            them: finished ? json["them"].lenientInt : nil,
            winner: finished ? json["winner"].string.flatMap(H2HWinner.init(rawValue:)) : nil, expiresAt: json["expires_at"].string,
            sessionID: json["session_id"].lenientString)
    }
}

public struct H2HList: JSONBacked, Sendable, Hashable {
    public var matches: [H2HMatch]

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        matches = json["matches"].models(H2HMatch.self)
    }
}

// MARK: Boards

public enum BoardScope: String, Sendable, Hashable, CaseIterable {
    case global, friends
}

public enum BoardWeek: String, Sendable, Hashable, CaseIterable {
    case current, previous
}

public struct BoardRow: Sendable, Hashable, Identifiable {
    public var rank: Int
    public var handle: String
    public var score: Int
    /// Only for users who opted in with `show_level`.
    public var level: Int?
    public var isYou: Bool

    public var id: String { handle }

    public init(rank: Int, handle: String, score: Int, level: Int? = nil, isYou: Bool = false) {
        self.rank = rank
        self.handle = handle
        self.score = score
        self.level = level
        self.isYou = isYou
    }

    init?(json: JSONValue) {
        guard let handle = json["handle"].string, !handle.isEmpty, let rank = json["rank"].lenientInt else { return nil }
        self.init(
            rank: rank, handle: handle, score: json["score"].lenientInt ?? 0, level: json["level"].lenientInt,
            isYou: json["you"].lenientBool ?? false)
    }
}

extension BoardRow: JSONBacked {
    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }
}

/// The caller's own standing. `rank` is nil when they are not on the board (no points, or not opted in).
public struct BoardYou: Sendable, Hashable {
    public var rank: Int?
    public var score: Int
    public var optedIn: Bool

    public init(rank: Int? = nil, score: Int = 0, optedIn: Bool = false) {
        self.rank = rank
        self.score = score
        self.optedIn = optedIn
    }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        self.init(rank: json["rank"].lenientInt, score: json["score"].lenientInt ?? 0, optedIn: json["opted_in"].lenientBool ?? false)
    }
}

/// `GET /play/leaderboard`. Handles only; `you` is nil without a handle.
public struct Leaderboard: JSONBacked, Sendable, Hashable {
    /// ISO week such as `2026-W46`.
    public var week: String
    public var rows: [BoardRow]
    public var you: BoardYou?

    public init(week: String = "", rows: [BoardRow] = [], you: BoardYou? = nil) {
        self.week = week
        self.rows = rows
        self.you = you
    }

    public init(from decoder: any Decoder) throws { self = try Self.read(decoder) }

    init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        self.init(week: json["week"].string ?? "", rows: json["rows"].models(BoardRow.self), you: BoardYou(json: json["you"]))
    }
}
