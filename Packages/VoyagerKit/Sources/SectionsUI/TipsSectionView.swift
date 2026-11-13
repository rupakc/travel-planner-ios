import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Travel tips (api-contract 3.4.10): title, body, severity tint, source link.
public struct TipsSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let tips = Info.list(data, "tips")
        if tips.isEmpty {
            InfoEmpty(key: K.results.tips.none)
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in card(tip) }
            }
        }
    }

    private func card(_ tip: JSONValue) -> some View {
        let severity = Info.text(tip["severity"])
        let warning = severity == "warning" || severity == "danger"
        return VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    if warning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.color(.amber, .s600))
                            .accessibilityLabel(L10n.text(K.sections.drawer.severity.warning))
                    }
                    Text(verbatim: Info.text(tip["title"]) ?? "")
                        .font(VFont.body(.subheadline, weight: .semibold))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let category = Info.text(tip["category"]) {
                    InfoTag(title: category.replacingOccurrences(of: "_", with: " "), family: warning ? .amber : .gray)
                }
                InfoLine(label: nil, value: Info.text(tip["body"]))
                HStack {
                    InfoLink(
                        title: L10n.text(K.results.tips.source), url: Info.httpsURL(tip["source_url"]), section: "tips",
                        ctx: ctx)
                    Spacer(minLength: 0)
                    PlanToggle(field: "tips", item: tip, ctx: ctx)
                }
            }
        }
    }
}
