import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The Travel Ease header (api-contract 3.4.17): total out of 100 in the grade colour (green at 71 and above,
/// amber at 41 and above, else red) plus the five sub-scores.
public struct ConfidenceHeaderView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    static func family(for grade: ConfidenceGrade) -> Family {
        switch grade {
        case .green: .green
        case .amber: .amber
        case .red: .red
        }
    }

    private static let order = [
        "visa_ease", "safety", "english_friendliness", "cost_vs_budget", "tourist_infrastructure",
    ]

    public var body: some View {
        if let total = data["total"].double, total.isFinite {
            let family = Self.family(for: ConfidenceGrade.grade(of: data))
            VCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                        Text(verbatim: String(Int(total.rounded())))
                            .font(VFont.display(.largeTitle))
                            .foregroundStyle(Palette.color(family, .s700))
                            .padding(.horizontal, Spacing.md)
                            .background(Palette.color(family, .s100), in: RoundedRectangle(cornerRadius: Radius.input))
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(verbatim: L10n.text(K.results.confidence.title))
                                .font(VFont.body(.subheadline, weight: .semibold))
                                .foregroundStyle(SemanticColor.text)
                            InfoLine(label: nil, value: Info.text(data["destination"]))
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    let subs = data["sub_scores"]
                    ForEach(Self.order.filter { subs[$0].object != nil }, id: \.self) { key in
                        subScore(subs[key], family: family)
                    }
                }
            }
        }
    }

    private func subScore(_ sub: JSONValue, family: Family) -> some View {
        let score = sub["score"].double ?? 0
        let max = Swift.max(sub["max"].double ?? 20, 1)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(verbatim: Info.text(sub["label"]) ?? "")
                    .font(VFont.body(.footnote, weight: .medium))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                Text(verbatim: "\(Int(score.rounded()))/\(Int(max.rounded()))")
                    .font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.textMuted)
            }
            ProgressView(value: Swift.min(Swift.max(score, 0), max), total: max)
                .tint(Palette.color(family, .s600))
            InfoLine(label: nil, value: Info.text(sub["note"]))
        }
        .accessibilityElement(children: .combine)
    }
}
