import Foundation
import L10n
import VoyagerModel

/// The words and numbers of the savings tally, from the server's `Savings` and nothing else: the app never sums,
/// converts or re-derives a milestone. Wording is "drops caught", never "saved".
enum SavingsText {
    struct MilestoneChip: Equatable {
        var amount: Int
        var reached: Bool
        var text: String
    }

    /// "Drops caught: $245.00", only when USD was caught (other currencies are listed apart, unconverted).
    static func totalLine(_ savings: Savings) -> String? {
        guard savings.totalUSD > 0 else { return nil }
        return L10n.text(K.savings.amountLine, ["amount": Fmt.currency(savings.totalUSD, code: "USD")])
    }

    /// "4 drops caught · 1 target hit".
    static func countsLine(_ savings: Savings) -> String {
        var line = L10n.text(K.savings.drops, count: savings.dropsCaught)
        if savings.targetsHit > 0 { line += " · " + L10n.text(K.savings.targets, count: savings.targetsHit) }
        return line
    }

    /// "24% of the way to $1,000", or "Every milestone reached" once no milestone is left.
    static func progressText(_ savings: Savings) -> String {
        guard let next = savings.nextMilestone else { return L10n.text(K.savings.allDone) }
        return L10n.text(
            K.savings.progress,
            ["pct": Fmt.number(Double(clampedPercent(savings)), fractionDigits: 0), "amount": Fmt.currency(Double(next), code: "USD")])
    }

    static func clampedPercent(_ savings: Savings) -> Int { max(0, min(100, savings.progressPct)) }

    /// 0...1 for the progress bar: full once every milestone is reached.
    static func progressFraction(_ savings: Savings) -> Double {
        savings.nextMilestone == nil ? 1 : Double(clampedPercent(savings)) / 100
    }

    /// "€12.00" per non-USD currency, as the server reported it.
    static func currencyLines(_ savings: Savings) -> [String] {
        savings.currencyLines.map { Fmt.currency($0.amount, code: $0.code) }
    }

    static func milestoneChips(_ savings: Savings) -> [MilestoneChip] {
        savings.milestones.sorted().map { milestone in
            let reached = savings.totalUSD >= Double(milestone)
            let amount = Fmt.currency(Double(milestone), code: "USD")
            return MilestoneChip(
                amount: milestone, reached: reached,
                text: L10n.text(reached ? K.savings.milestoneReached : K.savings.milestoneAhead, ["amount": amount]))
        }
    }

    /// "Best catch: Lumen Hotel, €46.00".
    static func bestText(_ savings: Savings) -> String? {
        guard let best = savings.best, best.caught > 0 else { return nil }
        let amount = Fmt.currency(best.caught, code: best.currency ?? "USD")
        if let title = best.title, !title.isEmpty { return L10n.text(K.savings.best, ["title": title, "amount": amount]) }
        return L10n.text(K.savings.bestNoTitle, ["amount": amount])
    }
}
