import DesignSystem
import L10n
import SwiftUI

/// The printable plan. Always light, at a fixed text size, whatever the app's theme: paper is white
/// (the web's print rule). `PrintRenderer` renders each block on its own so a page never cuts a row in half.
@MainActor
struct PlanPrintView {
    let document: PlanPrintDocument

    /// The pieces the renderer lays out on pages, in order.
    @MainActor var chunks: [AnyView] {
        var result: [AnyView] = [AnyView(header)]
        if !document.costParts.isEmpty { result.append(AnyView(cost)) }
        for block in document.blocks { result.append(AnyView(blockView(block, heading: true))) }
        if !document.days.isEmpty {
            result.append(
                AnyView(
                    Text(verbatim: L10n.text(K.plan.print.section.itinerary))
                        .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)))
            for day in document.days { result.append(AnyView(blockView(day, heading: false))) }
        }
        result.append(AnyView(footer))
        return result.map { AnyView(Self.page($0)) }
    }

    /// One chunk as printed: fixed text size, light scheme, white paper.
    @MainActor static func page(_ content: some View) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.md)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
            .background(Color.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: document.name).font(VFont.display(.title)).foregroundStyle(SemanticColor.text)
            if let line = document.tripLine {
                Text(verbatim: line).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            }
            if let source = document.inspiredBy {
                Text(verbatim: source).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    private var cost: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(K.plan.cost.heading)).font(VFont.display(.headline)).foregroundStyle(SemanticColor.text)
            ForEach(document.costParts) { part in
                HStack {
                    Text(verbatim: CostBreakdownView.label(for: part)).font(VFont.body(.subheadline))
                    Spacer(minLength: Spacing.sm)
                    Text(verbatim: Fmt.currency(part.amount, code: "USD")).font(VFont.body(.subheadline))
                }
                .foregroundStyle(SemanticColor.text)
            }
            HStack {
                Text(verbatim: L10n.text(K.plan.cost.total)).font(VFont.body(.subheadline, weight: .semibold))
                Spacer(minLength: Spacing.sm)
                Text(verbatim: Fmt.currency(document.total, code: "USD")).font(VFont.body(.subheadline, weight: .semibold))
            }
            .foregroundStyle(SemanticColor.text)
        }
    }

    private func blockView(_ block: PlanPrintDocument.Block, heading: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: block.title)
                .font(heading ? VFont.display(.headline) : VFont.display(.subheadline))
                .foregroundStyle(SemanticColor.text)
            ForEach(block.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: row.title).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                        if let detail = row.detail {
                            Text(verbatim: detail).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        }
                    }
                    Spacer(minLength: Spacing.sm)
                    if let price = row.price {
                        Text(verbatim: Fmt.currency(price, code: "USD"))
                            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text(verbatim: L10n.text(K.plan.print.footer)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
    }
}
