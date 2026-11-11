import DesignSystem
import L10n
import SwiftUI

/// A price in the app language. A missing or non-finite amount shows "—". `estimate` appends the Estimate tag
/// (estimates are always labelled).
public struct PriceText: View {
    private let amount: Double?
    private let currency: String
    private let estimate: Bool

    public init(amount: Double?, currency: String = "USD", estimate: Bool) {
        self.amount = amount
        self.currency = currency
        self.estimate = estimate
    }

    static func formatted(_ amount: Double?, currency: String) -> String {
        guard let amount else { return "—" }
        return Fmt.currency(amount, code: currency)
    }

    public var body: some View {
        let price = Text(verbatim: Self.formatted(amount, currency: currency))
            .font(VFont.body(.headline, weight: .semibold))
            .foregroundStyle(SemanticColor.text)
        Group {
            if estimate {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.sm) {
                        price
                        EstimateLabel()
                    }
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        price
                        EstimateLabel()
                    }
                }
            } else {
                price
            }
        }
        .accessibilityElement(children: .combine)
    }
}
