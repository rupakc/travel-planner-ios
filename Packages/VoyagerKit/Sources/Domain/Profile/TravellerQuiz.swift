import Foundation
import VoyagerModel

/// Traveller types. Declaration order is the classifier's tie-break order (same as Android, raw names too).
public enum TravellerType: String, CaseIterable, Sendable, Hashable, Codable {
    case budgetBackpacker = "BUDGET_BACKPACKER"
    case family = "FAMILY"
    case luxury = "LUXURY"
    case adventure = "ADVENTURE"
    case cultureFoodie = "CULTURE_FOODIE"
    case business = "BUSINESS"
    case relaxation = "RELAXATION"
    /// Added as a secondary whenever any accessibility need is chosen; never hides other types.
    case accessible = "ACCESSIBLE"

    var order: Int { Self.allCases.firstIndex(of: self) ?? Int.max }
}

/// Default traveller counts a "who do you travel with" answer pre-fills.
public struct TravellerCounts: Sendable, Hashable {
    public let adults: Int
    public let children: Int

    public init(adults: Int, children: Int = 0) {
        self.adults = adults
        self.children = children
    }
}

/// One answer option: classifier `weights` plus what it pre-fills on the server (`PUT /api/preferences`).
/// `pace` is a search-only field with no Preferences field.
public struct QuizOption: Sendable, Hashable {
    public let id: String
    public let weights: [TravellerType: Int]
    public let interestIDs: [String]
    public let budgetCategory: String?
    public let accessibilityID: String?
    public let travellers: TravellerCounts?
    public let addsInfant: Bool
    public let pace: String?

    public init(
        _ id: String,
        weights: [TravellerType: Int] = [:],
        interestIDs: [String] = [],
        budgetCategory: String? = nil,
        accessibilityID: String? = nil,
        travellers: TravellerCounts? = nil,
        addsInfant: Bool = false,
        pace: String? = nil
    ) {
        self.id = id
        self.weights = weights
        self.interestIDs = interestIDs
        self.budgetCategory = budgetCategory
        self.accessibilityID = accessibilityID
        self.travellers = travellers
        self.addsInfant = addsInfant
        self.pace = pace
    }
}

/// One question of the onboarding quiz. `id` is the key in the stored answers.
public struct QuizQuestion: Sendable, Hashable {
    public let id: String
    public let multiChoice: Bool
    public let options: [QuizOption]

    public init(id: String, multiChoice: Bool, options: [QuizOption]) {
        self.id = id
        self.multiChoice = multiChoice
        self.options = options
    }
}

/// THE quiz table, copied from Android's `TravellerQuiz.kt` (and its `docs/Onboarding-and-Traveller-Types.md`):
/// questions, options, scoring weights and the Preferences mapping in one place. Change both apps together.
public enum TravellerQuiz {
    public static let companions = "companions"
    public static let budget = "budget"
    public static let interests = "interests"
    public static let pace = "pace"
    public static let planning = "planning"
    public static let needs = "needs"

    /// Primary type when no answer scores (everything skipped).
    public static let defaultType = TravellerType.cultureFoodie

    /// Secondary threshold: second score is at least this percentage of the primary score.
    public static let secondaryPercent = 60

    public static let questions: [QuizQuestion] = [
        QuizQuestion(id: companions, multiChoice: false, options: [
            QuizOption("solo", weights: [.budgetBackpacker: 2, .adventure: 1], travellers: TravellerCounts(adults: 1)),
            QuizOption("partner", weights: [.relaxation: 2, .luxury: 1, .cultureFoodie: 1], travellers: TravellerCounts(adults: 2)),
            QuizOption("family_kids", weights: [.family: 4], interestIDs: ["family"], travellers: TravellerCounts(adults: 2, children: 1)),
            QuizOption("friends", weights: [.adventure: 2, .budgetBackpacker: 1], travellers: TravellerCounts(adults: 3)),
            QuizOption("work", weights: [.business: 4], travellers: TravellerCounts(adults: 1)),
        ]),
        QuizQuestion(id: budget, multiChoice: false, options: [
            QuizOption("shoestring", weights: [.budgetBackpacker: 3], budgetCategory: "low"),
            QuizOption("mid_range", weights: [.cultureFoodie: 1, .family: 1], budgetCategory: "medium"),
            QuizOption("comfort", weights: [.relaxation: 1, .business: 1], budgetCategory: "medium"),
            QuizOption("luxury", weights: [.luxury: 4], budgetCategory: "high"),
        ]),
        QuizQuestion(id: interests, multiChoice: true, options: [
            QuizOption("food", weights: [.cultureFoodie: 2], interestIDs: ["food"]),
            QuizOption("history_culture", weights: [.cultureFoodie: 2], interestIDs: ["history", "culture"]),
            QuizOption("nature", weights: [.adventure: 1, .relaxation: 1], interestIDs: ["nature"]),
            QuizOption("adventure", weights: [.adventure: 2], interestIDs: ["adventure"]),
            QuizOption("nightlife", weights: [.budgetBackpacker: 1], interestIDs: ["nightlife"]),
            QuizOption("shopping", weights: [.luxury: 1], interestIDs: ["shopping"]),
            QuizOption("art_museums", weights: [.cultureFoodie: 1], interestIDs: ["art"]),
            QuizOption("beaches", weights: [.relaxation: 2], interestIDs: ["nature", "wellness"]),
            QuizOption("photography", weights: [.adventure: 1, .cultureFoodie: 1], interestIDs: ["art"]),
            QuizOption("wellness", weights: [.relaxation: 1, .luxury: 1], interestIDs: ["wellness"]),
        ]),
        QuizQuestion(id: pace, multiChoice: false, options: [
            QuizOption("relaxed", weights: [.relaxation: 2, .family: 1], pace: "relaxed"),
            QuizOption("balanced", weights: [.cultureFoodie: 1], pace: "balanced"),
            QuizOption("packed", weights: [.adventure: 1, .business: 1, .budgetBackpacker: 1], pace: "packed"),
        ]),
        QuizQuestion(id: planning, multiChoice: false, options: [
            QuizOption("ahead_deals", weights: [.budgetBackpacker: 1, .family: 1]),
            QuizOption("loose", weights: [.cultureFoodie: 1, .relaxation: 1]),
            QuizOption("spontaneous", weights: [.adventure: 1, .budgetBackpacker: 1]),
        ]),
        QuizQuestion(id: needs, multiChoice: true, options: [
            QuizOption("wheelchair", accessibilityID: "wheelchair"),
            QuizOption("visual_impairment", accessibilityID: "visual_impairment"),
            QuizOption("hearing_impairment", accessibilityID: "hearing_impairment"),
            QuizOption("cognitive_disability", accessibilityID: "cognitive_disability"),
            QuizOption("infants", weights: [.family: 3], addsInfant: true),
            QuizOption("dietary"),
        ]),
    ]

    public static func question(_ id: String) -> QuizQuestion? {
        questions.first { $0.id == id }
    }

    /// Valid options chosen for `questionID`: unknown ids dropped, duplicates removed, and a single-choice
    /// question keeps only its first valid answer.
    public static func chosen(_ answers: [String: [String]], question questionID: String) -> [QuizOption] {
        guard let question = question(questionID) else { return [] }
        var seen = Set<String>()
        let picked = (answers[questionID] ?? []).compactMap { id -> QuizOption? in
            guard seen.insert(id).inserted else { return nil }
            return question.options.first { $0.id == id }
        }
        return question.multiChoice ? picked : Array(picked.prefix(1))
    }

    /// All valid chosen options across the quiz.
    public static func chosen(_ answers: [String: [String]]) -> [QuizOption] {
        questions.flatMap { chosen(answers, question: $0.id) }
    }

    /// True when any of the four accessibility needs was chosen (adds `.accessible` as a secondary).
    public static func hasAccessibilityNeed(_ answers: [String: [String]]) -> Bool {
        chosen(answers, question: needs).contains { $0.accessibilityID != nil }
    }

    /// The trip pace answer (`relaxed` / `balanced` / `packed`), or `nil` when skipped. Search-only, kept on the device.
    public static func pace(_ answers: [String: [String]]) -> String? {
        chosen(answers, question: pace).first?.pace
    }

    // MARK: - Preferences

    /// Server limit for traveller counts.
    private static let maxTravellers = 20

    /// The `PUT /api/preferences` fields this quiz fills, merged with `current` (the user's server preferences,
    /// `snake_case` keys) so nothing they have is wiped. Only changed fields are present.
    /// - `interests`, `accessibility_needs`: union (existing first), web ids only.
    /// - `budget_category`: set when the budget question was answered.
    /// - `adults` / `children`: from the companions answer, only while the server still holds the default party
    ///   (1 adult, nobody else); a party the user set is never overwritten. A missing `current` is the default party.
    /// - `infants`: at least 1 when "travelling with infants" was chosen (a minimum, never lowered).
    /// - `num_travelers`: adults + children + seniors + infants, clamped to 1...20, when a count changed.
    public static func preferencesPatch(_ answers: [String: [String]], current: JSONValue = .null) -> JSONValue {
        let options = chosen(answers)
        var patch: [String: JSONValue] = [:]

        let interestsNow = strings(current["interests"])
        let interestsOut = unique(interestsNow + options.flatMap(\.interestIDs))
        if interestsOut != interestsNow {
            patch["interests"] = .array(interestsOut.map(JSONValue.string))
        }
        let needsNow = strings(current["accessibility_needs"])
        let needsOut = unique(needsNow + options.compactMap(\.accessibilityID))
        if needsOut != needsNow {
            patch["accessibility_needs"] = .array(needsOut.map(JSONValue.string))
        }
        if let category = chosen(answers, question: budget).first?.budgetCategory,
           current["budget_category"].string != category {
            patch["budget_category"] = .string(category)
        }

        let adults = current["adults"].int ?? 1
        let children = current["children"].int ?? 0
        let seniors = current["seniors"].int ?? 0
        let infants = current["infants"].int ?? 0
        let defaultParty = adults == 1 && children == 0 && seniors == 0 && infants == 0
        let counts = defaultParty ? chosen(answers, question: companions).first?.travellers : nil
        let adultsOut = counts?.adults ?? adults
        let childrenOut = counts?.children ?? children
        let infantsOut = options.contains(where: \.addsInfant) ? max(infants, 1) : infants
        if adultsOut != adults { patch["adults"] = .number(Double(adultsOut)) }
        if childrenOut != children { patch["children"] = .number(Double(childrenOut)) }
        if infantsOut != infants { patch["infants"] = .number(Double(infantsOut)) }
        if adultsOut != adults || childrenOut != children || infantsOut != infants {
            let total = min(max(adultsOut + childrenOut + seniors + infantsOut, 1), maxTravellers)
            patch["num_travelers"] = .number(Double(total))
        }
        return .object(patch)
    }

    private static func strings(_ value: JSONValue) -> [String] {
        (value.array ?? []).compactMap(\.string)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
