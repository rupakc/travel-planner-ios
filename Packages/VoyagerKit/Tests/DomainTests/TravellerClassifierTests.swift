import Testing
import VoyagerModel
@testable import Domain

/// The cases of Android's `TravellerClassifierTest` (same inputs, same expected outputs), plus the preferences patch.
@Suite struct TravellerClassifierTests {
    typealias Answers = [String: [String]]

    private func classify(_ answers: Answers) -> (primary: TravellerType, secondary: [TravellerType]) {
        TravellerClassifier.classify(answers)
    }

    @Test func quizHasSixQuestionsWithUniqueIDsAndOptions() {
        #expect(TravellerQuiz.questions.map(\.id) == ["companions", "budget", "interests", "pace", "planning", "needs"])
        for question in TravellerQuiz.questions {
            #expect(Set(question.options.map(\.id)).count == question.options.count, "\(question.id)")
        }
        #expect(TravellerQuiz.questions.filter(\.multiChoice).map(\.id) == ["interests", "needs"])
    }

    @Test func typesKeepAndroidRawNamesAndOrder() {
        #expect(TravellerType.allCases.map(\.rawValue) == [
            "BUDGET_BACKPACKER", "FAMILY", "LUXURY", "ADVENTURE", "CULTURE_FOODIE", "BUSINESS", "RELAXATION", "ACCESSIBLE",
        ])
    }

    @Test func everyScoredTypeIsReachableAsPrimary() {
        let cases: [(TravellerType, Answers)] = [
            (.budgetBackpacker, ["companions": ["solo"], "budget": ["shoestring"]]),
            (.family, ["companions": ["family_kids"]]),
            (.luxury, ["budget": ["luxury"]]),
            (.adventure, ["interests": ["adventure"]]),
            (.cultureFoodie, ["interests": ["food"]]),
            (.business, ["companions": ["work"]]),
            (.relaxation, ["interests": ["beaches"]]),
        ]
        for (type, answers) in cases { #expect(classify(answers).primary == type, "\(type)") }
        #expect(Set(cases.map(\.0)) == Set(TravellerType.allCases).subtracting([.accessible]))
    }

    @Test(arguments: ["wheelchair", "visual_impairment", "hearing_impairment", "cognitive_disability"])
    func accessibleIsAddedForEachAccessibilityNeed(need: String) {
        let result = classify(["companions": ["work"], "needs": [need]])
        #expect(result.primary == .business)
        #expect(result.secondary == [.accessible])
    }

    @Test func accessibleComesAfterTheScoredSecondary() {
        let result = classify(["pace": ["packed"], "needs": ["wheelchair"]])
        #expect(result.primary == .budgetBackpacker)
        #expect(result.secondary == [.adventure, .accessible])
    }

    @Test func infantsAndDietaryDoNotAddAccessible() {
        let result = classify(["needs": ["infants", "dietary"]])
        #expect(result.primary == .family)
        #expect(result.secondary.isEmpty)
    }

    @Test func tiesAreBrokenByTheFixedTypeOrder() {
        // packed = ADVENTURE 1, BUSINESS 1, BUDGET_BACKPACKER 1
        let packed = classify(["pace": ["packed"]])
        #expect(packed.primary == .budgetBackpacker)
        #expect(packed.secondary == [.adventure])
        // loose = CULTURE_FOODIE 1, RELAXATION 1
        let loose = classify(["planning": ["loose"]])
        #expect(loose.primary == .cultureFoodie)
        #expect(loose.secondary == [.relaxation])
    }

    @Test func secondaryNeedsAtLeastSixtyPercentOfThePrimaryScore() {
        // LUXURY 5, RELAXATION 3, CULTURE_FOODIE 1: 3/5 = 60 percent, so it is a secondary.
        let atThreshold: Answers = ["budget": ["luxury"], "interests": ["shopping", "beaches"], "planning": ["loose"]]
        let nonZero = TravellerClassifier.scores(atThreshold).filter { $0.value > 0 }
        #expect(nonZero == [.luxury: 5, .relaxation: 3, .cultureFoodie: 1])
        let result = classify(atThreshold)
        #expect(result.primary == .luxury)
        #expect(result.secondary == [.relaxation])

        // LUXURY 5, RELAXATION 2: 40 percent, so none.
        let below = classify(["budget": ["luxury"], "interests": ["shopping", "beaches"]])
        #expect(below.primary == .luxury)
        #expect(below.secondary.isEmpty)
    }

    @Test func onlyOneScoredSecondaryEvenWhenSeveralQualify() {
        // partner: RELAXATION 2, LUXURY 1, CULTURE_FOODIE 1, plus food: CULTURE_FOODIE 3 gives CF 3, R 2, L 1.
        let result = classify(["companions": ["partner"], "interests": ["food"]])
        #expect(result.primary == .cultureFoodie)
        #expect(result.secondary == [.relaxation])
    }

    @Test func emptyOrSkippedAnswersGiveTheDefaultType() {
        #expect(TravellerQuiz.defaultType == .cultureFoodie)
        for answers: Answers in [[:], ["companions": [], "interests": []], ["needs": ["dietary"]]] {
            let result = classify(answers)
            #expect(result.primary == .cultureFoodie)
            #expect(result.secondary.isEmpty)
        }
    }

    @Test func unknownQuestionsAndOptionsAreIgnored() {
        let result = classify(["bogus": ["work"], "companions": ["aliens"]])
        #expect(result.primary == .cultureFoodie)
        #expect(result.secondary.isEmpty)
    }

    @Test func singleChoiceQuestionsOnlyCountTheFirstValidAnswer() {
        #expect(classify(["companions": ["nope", "work", "family_kids"]]).primary == .business)
    }

    @Test func duplicateAnswersCountOnce() {
        let scores = TravellerClassifier.scores(["interests": ["food", "food"]]).filter { $0.value > 0 }
        #expect(scores == [.cultureFoodie: 2])
    }

    @Test func classificationIsDeterministic() {
        let answers: Answers = ["companions": ["friends"], "interests": ["adventure", "nightlife", "food"], "pace": ["packed"]]
        let first = classify(answers)
        for _ in 0..<5 {
            let again = classify(answers)
            #expect(again.primary == first.primary)
            #expect(again.secondary == first.secondary)
        }
    }

    @Test func everyOptionWeightTargetsAScoredType() {
        for option in TravellerQuiz.questions.flatMap(\.options) {
            #expect(!option.weights.keys.contains(.accessible), "\(option.id)")
            #expect(option.weights.values.allSatisfy { $0 > 0 }, "\(option.id)")
        }
    }

    // MARK: - Preferences patch

    @Test func patchFillsTheDefaultPartyAndWebIDs() {
        let patch = TravellerQuiz.preferencesPatch([
            "companions": ["family_kids"], "budget": ["luxury"],
            "interests": ["history_culture", "beaches", "photography"], "needs": ["wheelchair", "infants"],
        ])
        #expect(patch["interests"] == ["family", "history", "culture", "nature", "wellness", "art"])
        #expect(patch["accessibility_needs"] == ["wheelchair"])
        #expect(patch["budget_category"] == "high")
        #expect(patch["adults"] == 2)
        #expect(patch["children"] == 1)
        #expect(patch["infants"] == 1)
        #expect(patch["num_travelers"] == 4)
    }

    @Test func patchNeverOverwritesAPartyTheUserSet() {
        let current: JSONValue = ["adults": 2, "children": 2, "seniors": 0, "infants": 0, "interests": ["food"], "budget_category": "low"]
        let patch = TravellerQuiz.preferencesPatch(
            ["companions": ["solo"], "interests": ["food", "nature"], "needs": ["infants"]], current: current)
        #expect(patch["adults"].isNull)
        #expect(patch["children"].isNull)
        #expect(patch["infants"] == 1)
        #expect(patch["num_travelers"] == 5)
        #expect(patch["interests"] == ["food", "nature"])
        #expect(patch["budget_category"].isNull)
    }

    @Test func patchKeepsInfantsAtLeastTheCurrentCount() {
        let current: JSONValue = ["adults": 2, "children": 0, "seniors": 0, "infants": 2]
        let patch = TravellerQuiz.preferencesPatch(["needs": ["infants"]], current: current)
        #expect(patch == .object([:]))
    }

    @Test func patchOfNothingIsEmptyAndTravellersAreClamped() {
        #expect(TravellerQuiz.preferencesPatch([:]) == .object([:]))
        let patch = TravellerQuiz.preferencesPatch(
            ["needs": ["infants"]], current: ["adults": 1, "children": 0, "seniors": 19, "infants": 0])
        #expect(patch["num_travelers"] == 20)
    }

    @Test func paceAnswerIsExposedForTheSearchForm() {
        #expect(TravellerQuiz.pace(["pace": ["packed"]]) == "packed")
        #expect(TravellerQuiz.pace([:]) == nil)
    }
}
