import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// One suggestion: city, country, weather emoji, visa badge, up to two match reasons, "Plan this trip".
struct DestinationCard: View {
    let suggestion: DiscoverSuggestion
    let index: Int
    let onPlan: () -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(verbatim: suggestion.city ?? "")
                            .font(VFont.display(.headline))
                            .foregroundStyle(SemanticColor.text)
                        if let country = suggestion.country {
                            Text(verbatim: country)
                                .font(VFont.body(.subheadline))
                                .foregroundStyle(SemanticColor.textMuted)
                        }
                    }
                    Spacer(minLength: Spacing.sm)
                    Text(verbatim: Self.emoji(suggestion.weatherEmoji))
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                }
                if let visa = Self.visaLabel(suggestion.visaType) {
                    Text(verbatim: visa)
                        .font(VFont.body(.caption, weight: .medium))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(SemanticColor.surface, in: Capsule())
                        .foregroundStyle(SemanticColor.text)
                }
                if let low = suggestion.estimatedCostUsdLow, let high = suggestion.estimatedCostUsdHigh {
                    Text(verbatim: L10n.text(
                        K.search.discover.costRange, ["low": String(Int(low)), "high": String(Int(high))]))
                        .font(VFont.body(.footnote))
                        .foregroundStyle(SemanticColor.textMuted)
                }
                ForEach(Array((suggestion.matchReasons ?? []).prefix(2).enumerated()), id: \.offset) { _, reason in
                    Text(verbatim: "✓ \(reason)")
                        .font(VFont.body(.footnote))
                        .foregroundStyle(SemanticColor.text)
                }
                VButton(L10n.text(K.search.discover.planThisTrip), tid: "discover.plan.\(index)", action: onPlan)
            }
        }
    }

    static func emoji(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "🌍" }
        return value
    }

    static func visaLabel(_ type: String?) -> String? {
        guard let type = type?.lowercased(), !type.isEmpty else { return nil }
        if type.contains("free") || type == "none" { return L10n.text(K.search.discover.visaFree) }
        if type.contains("arrival") { return L10n.text(K.search.discover.visaOnArrival) }
        if type.contains("evisa") || type.contains("e-visa") { return L10n.text(K.search.discover.eVisa) }
        if type.contains("required") { return L10n.text(K.search.discover.visaRequired) }
        return L10n.text(K.search.discover.visaVerify)
    }
}
