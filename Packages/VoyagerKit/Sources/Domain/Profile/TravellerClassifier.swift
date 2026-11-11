import Foundation

/// Weighted-score classifier over `TravellerQuiz`. Pure and deterministic:
/// - score per type = sum of the chosen options' weights;
/// - primary = highest score, ties broken by `TravellerType` declaration order;
/// - one scored secondary = the runner-up when its score is at least `TravellerQuiz.secondaryPercent` % of the primary;
/// - `.accessible` is appended when any accessibility need is chosen;
/// - nothing scored (all skipped) gives `TravellerQuiz.defaultType` and no scored secondary.
public enum TravellerClassifier {
    public static func classify(_ answers: [String: [String]]) -> (primary: TravellerType, secondary: [TravellerType]) {
        let ranked = scores(answers)
            .filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.order < $1.key.order }
        let primary = ranked.first?.key ?? TravellerQuiz.defaultType
        let top = ranked.first?.value ?? 0
        var secondary: [TravellerType] = []
        if ranked.count > 1, ranked[1].value * 100 >= top * TravellerQuiz.secondaryPercent {
            secondary.append(ranked[1].key)
        }
        if TravellerQuiz.hasAccessibilityNeed(answers), primary != .accessible, !secondary.contains(.accessible) {
            secondary.append(.accessible)
        }
        return (primary, secondary)
    }

    /// Raw score per type (every type present, 0 when unscored).
    public static func scores(_ answers: [String: [String]]) -> [TravellerType: Int] {
        var totals = Dictionary(uniqueKeysWithValues: TravellerType.allCases.map { ($0, 0) })
        for option in TravellerQuiz.chosen(answers) {
            for (type, weight) in option.weights { totals[type, default: 0] += weight }
        }
        return totals
    }
}
