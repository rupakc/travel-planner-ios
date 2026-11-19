import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// "≈ N kg CO₂e" for one flight result, from Google's Travel Impact Model (the web's `EmissionsChip`). Nothing when
/// the backend sent no usable `emissions` (an older backend, the feature off, or a flight TIM can't estimate). Tapping
/// shows the per-class breakdown and the CC BY-SA attribution, which links to TIM.
struct EmissionsChip: View {
    struct Content: Equatable {
        let chip: String
        /// "Business: 201 kg", in the order economy, premium economy, business, first.
        let classLines: [String]
        let url: URL
    }

    static let defaultURL = URL(string: "https://travelimpactmodel.org")

    private static let classes: [(key: String, label: LKey)] = [
        ("economy", K.results.emissions.class.economy),
        ("premiumEconomy", K.results.emissions.class.premiumEconomy),
        ("business", K.results.emissions.class.business),
        ("first", K.results.emissions.class.first),
    ]

    let emissions: JSONValue
    @State private var presented = false
    @Environment(\.telemetryRoute) private var route

    static func content(_ emissions: JSONValue) -> Content? {
        guard case .number(let kg) = emissions["kg_co2e_per_pax"], kg.isFinite,
              let url = attributionURL(emissions["attribution_url"]) ?? defaultURL else { return nil }
        let byClass = emissions["by_class"]
        let lines = classes.compactMap { entry -> String? in
            guard case .number(let value) = byClass[entry.key], value.isFinite else { return nil }
            return L10n.text(K.results.emissions.classLine, ["cls": L10n.text(entry.label), "kg": Fmt.number(value)])
        }
        return Content(chip: L10n.text(K.results.emissions.chip, ["kg": Fmt.number(kg)]), classLines: lines, url: url)
    }

    private static func attributionURL(_ value: JSONValue) -> URL? {
        guard let raw = value.string, raw.lowercased().hasPrefix("https://"), let url = URL(string: raw), url.host != nil else {
            return nil
        }
        return url
    }

    var body: some View {
        if let content = Self.content(emissions) {
            Button {
                Telemetry.shared.track(.uiTap(tid: "results.flight.emissions", route: route))
                presented = true
            } label: {
                Label {
                    Text(verbatim: content.chip)
                } icon: {
                    Image(systemName: "leaf")
                }
                .font(VFont.body(.caption, weight: .medium))
                .foregroundStyle(Palette.color(.emerald, .s700))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .borderedSurface(Capsule(), fill: Palette.color(.emerald, .s50), border: Palette.color(.emerald, .s200))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                ([content.chip, L10n.text(K.results.emissions.perPassenger)] + content.classLines
                    + [L10n.text(K.results.emissions.attribution)]).joined(separator: ". "))
            .accessibilityIdentifier("results.flight.emissions")
            .popover(isPresented: $presented) {
                EmissionsDetails(content: content)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

private struct EmissionsDetails: View {
    let content: EmissionsChip.Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(K.results.emissions.perPassenger))
                .font(VFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
            ForEach(content.classLines, id: \.self) { line in
                Text(verbatim: line)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.text)
            }
            Link(destination: content.url) {
                Text(verbatim: L10n.text(K.results.emissions.attribution))
                    .font(VFont.body(.footnote, weight: .medium))
                    .multilineTextAlignment(.leading)
            }
            .tint(SemanticColor.primary)
            .accessibilityIdentifier("results.flight.emissions.source")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Spacing.lg)
        .frame(minWidth: 240, alignment: .leading)
        .background(SemanticColor.surfaceRaised)
    }
}
