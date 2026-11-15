import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The savings tally: "Drops caught: $245.00", counts, progress to the next milestone (50, 200, 1000), the milestone
/// chips, other currencies unconverted, the best catch and, when share links 2.0 exist, a Share button.
/// Shows nothing on a backend without Alerts 2.0.
struct SavingsHeader: View {
    let model: AlertsHeaderModel

    var body: some View {
        switch model.phase {
        case .idle, .unavailable:
            EmptyView()
        case .loading:
            VCard {
                HStack(spacing: Spacing.md) {
                    ProgressView()
                    Text(verbatim: L10n.text(K.alerts.page.loading))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                }
            }
            .accessibilityIdentifier("alerts.savings.loading")
        case .failed(let message):
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(verbatim: message)
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    VButton(L10n.text(K.alerts.ui.retry), tid: "alerts.savings.retry", role: .secondary) {
                        Task { await model.load() }
                    }
                }
            }
        case .loaded(let savings):
            if savings.isEmpty { empty } else { tally(savings) }
        }
    }

    private var empty: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.savings.empty))
                    .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                Text(verbatim: L10n.text(K.savings.emptyHint))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("alerts.savings.empty")
    }

    private func tally(_ savings: Savings) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let total = SavingsText.totalLine(savings) {
                        // "Drops caught: $245.00" is its own heading; the plain title only stands in when no USD was caught.
                        Text(verbatim: total)
                            .font(VFont.display(.title3)).foregroundStyle(SemanticColor.primary)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("alerts.savings.total")
                    } else {
                        Text(verbatim: L10n.text(K.savings.title))
                            .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text(verbatim: SavingsText.countsLine(savings))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .accessibilityIdentifier("alerts.savings.counts")
                }
                .fixedSize(horizontal: false, vertical: true)
                progress(savings)
                milestones(savings)
                currencies(savings)
                if let best = SavingsText.bestText(savings) {
                    Text(verbatim: best)
                        .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("alerts.savings.best")
                }
                Text(verbatim: L10n.text(K.savings.caveat))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .fixedSize(horizontal: false, vertical: true)
                if model.canShare {
                    VButton(L10n.text(K.savings.share), tid: "alerts.savings.share", role: .secondary) {
                        model.shareSavings()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alerts.savings")
    }

    private func progress(_ savings: Savings) -> some View {
        let text = SavingsText.progressText(savings)
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            ProgressTrack(fraction: SavingsText.progressFraction(savings))
                .frame(height: 8)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("alerts.savings.progress")
    }

    private func milestones(_ savings: Savings) -> some View {
        AlertsWrapLayout(spacing: Spacing.sm) {
            ForEach(SavingsText.milestoneChips(savings), id: \.amount) { chip in
                Text(verbatim: chip.text)
                    .font(VFont.body(.footnote, weight: .medium))
                    .foregroundStyle(chip.reached ? SemanticColor.onPrimary : SemanticColor.textMuted)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
                    .borderedSurface(
                        Capsule(), fill: chip.reached ? SemanticColor.primary : SemanticColor.surface,
                        border: chip.reached ? nil : SemanticColor.border)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text(K.savings.milestones))
    }

    @ViewBuilder private func currencies(_ savings: Savings) -> some View {
        let lines = SavingsText.currencyLines(savings)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.savings.otherCurrencies))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                AlertsWrapLayout(spacing: Spacing.sm) {
                    ForEach(lines, id: \.self) { line in
                        Text(verbatim: line)
                            .font(VFont.body(.footnote, weight: .medium)).foregroundStyle(SemanticColor.text)
                            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.xs)
                            .borderedSurface(Capsule(), fill: SemanticColor.surface, border: SemanticColor.border)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("alerts.savings.currencies")
        }
    }
}

/// A rounded progress bar, 0...1.
private struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SemanticColor.border)
                Capsule().fill(SemanticColor.primary)
                    .frame(width: max(8, proxy.size.width * min(1, max(0, fraction))))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
    }
}
