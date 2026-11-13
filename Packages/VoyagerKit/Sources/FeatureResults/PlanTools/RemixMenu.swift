import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// One-tap "what if" presets; each re-runs the search with the preset applied.
struct RemixMenu: View {
    let searchData: JSONValue?
    let onRemix: (RemixPreset) -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text(verbatim: L10n.text(K.sections.remix.title)).font(VFont.body(.headline, weight: .semibold))
                    } icon: {
                        Image(systemName: "wand.and.stars").foregroundStyle(SemanticColor.primary)
                    }
                    Text(verbatim: L10n.text(K.sections.remix.blurb)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Remix.presets) { preset in
                        let ok = PlanToolsModel.isApplicable(preset, searchData: searchData)
                        VButton(
                            "\(preset.emoji) \(PlanTranslator.text(preset.labelKey, [:]))", tid: "remix.preset.\(preset.id)",
                            role: .tonal) { onRemix(preset) }
                            .disabled(!ok)
                            .accessibilityHint(
                                ok ? PlanTranslator.text(preset.descriptionKey, [:]) : L10n.text(K.sections.remix.notApplicable))
                    }
                }
            }
        }
        .accessibilityIdentifier("results.remix")
    }
}

/// Before/after of the key numbers once the remixed search finished.
struct RemixDiffBanner: View {
    let baseline: RemixBaseline
    let results: JSONValue
    let onDismiss: () -> Void

    var body: some View {
        let rows = Remix.diffMetrics(baseline.before, Remix.snapshotMetrics(results), translate: PlanTranslator.text)
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top) {
                    Text(verbatim: L10n.text(K.sections.remix.banner, ["label": PlanTranslator.text("sections:remix.preset.\(baseline.presetID).label", [:])]))
                        .font(VFont.body(.subheadline, weight: .semibold))
                    Spacer(minLength: Spacing.sm)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(L10n.text(K.sections.remix.dismiss))
                }
                if rows.isEmpty {
                    Text(verbatim: L10n.text(K.sections.remix.notEnough)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in metric(row) }
                }
            }
        }
        .accessibilityIdentifier("results.remixDiff")
    }

    private func metric(_ row: JSONValue) -> some View {
        let kind = row["kind"].string ?? "count"
        let before = row["before"].double ?? 0, after = row["after"].double ?? 0, delta = row["delta"].double ?? 0
        let direction = row["direction"].string ?? "same"
        let improved = row["improved"].isTruthy
        return HStack(alignment: .firstTextBaseline) {
            Text(verbatim: row["label"].string ?? "").font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            Spacer(minLength: Spacing.sm)
            Text(verbatim: PlanToolsFormat.metric(after, kind: kind)).font(VFont.body(.subheadline, weight: .bold))
            Text(verbatim: PlanToolsFormat.metric(before, kind: kind))
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted).strikethrough()
            if direction != "same" {
                Label(PlanToolsFormat.metric(abs(delta), kind: kind), systemImage: direction == "down" ? "arrow.down" : "arrow.up")
                    .font(VFont.body(.caption, weight: .semibold))
                    .foregroundStyle(improved ? SemanticColor.primary : SemanticColor.destructive)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
