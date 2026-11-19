import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// One watch line of the weekly digest, already worded.
struct DigestLine: Equatable, Identifiable {
    var id: Int
    var title: String
    var latest: String?
    /// "-$12.00" / "+$8.00" over the last 7 days (sign by the locale); nil when the server had no base to compare with.
    var change: String?
    /// The 7-day change as a number: the colour follows its sign, never the text.
    var changeDelta: Double?
    var lowest: String?
}

/// The weekly digest's watches as the inbox shows them. Tolerant: any field may be missing, an unknown kind or an
/// untitled watch still gives a line, and a digest with no watches gives none.
enum DigestContent {
    static func lines(_ digest: DigestData) -> [DigestLine] {
        digest.watches.enumerated().map { index, watch in
            let price: (Double) -> String = { amount in
                watch.currency.map { Fmt.currency(amount, code: $0) } ?? Fmt.number(amount, fractionDigits: 2)
            }
            let change = watch.change7d.flatMap { delta -> String? in
                guard delta != 0 else { return nil }
                return watch.currency.map { Fmt.signedCurrency(delta, code: $0) }
                    ?? Fmt.number(delta, fractionDigits: 2, signed: true)
            }
            return DigestLine(
                id: index, title: watch.title ?? "", latest: watch.latest.map(price), change: change,
                changeDelta: change == nil ? nil : watch.change7d,
                lowest: watch.lowest.map { L10n.text(K.priceStory.chart.lowest, ["price": price($0)]) })
        }
    }

    /// "Drops caught: $245.00" from the digest's own savings, when there is a USD total.
    static func savingsLine(_ digest: DigestData) -> String? { digest.savings.flatMap(SavingsText.totalLine) }
}

/// The `price_digest` row's summary: each watch's last price, its 7-day change and its lowest, and the savings line.
struct DigestRow: View {
    let digest: DigestData

    var body: some View {
        let lines = DigestContent.lines(digest)
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            title(line)
                            Spacer(minLength: Spacing.sm)
                            price(line)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            title(line)
                            price(line)
                        }
                    }
                    if let lowest = line.lowest {
                        Text(verbatim: lowest)
                            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let savings = DigestContent.savingsLine(digest) {
                Text(verbatim: savings)
                    .font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.primary)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .borderedSurface(
            RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surface, border: SemanticColor.border)
        .accessibilityIdentifier("inbox.digest")
    }

    private func title(_ line: DigestLine) -> some View {
        Text(verbatim: line.title)
            .font(VFont.body(.subheadline, weight: .medium)).foregroundStyle(SemanticColor.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func price(_ line: DigestLine) -> some View {
        HStack(spacing: Spacing.xs) {
            if let latest = line.latest {
                Text(verbatim: latest).fontWeight(.semibold).foregroundStyle(SemanticColor.text)
            }
            if let change = line.change {
                Text(verbatim: change)
                    .foregroundStyle((line.changeDelta ?? 0) < 0 ? SemanticColor.primary : SemanticColor.textMuted)
            }
        }
        .font(VFont.body(.subheadline))
    }
}
