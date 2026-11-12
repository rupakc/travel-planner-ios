import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The fallback body for a section: its main list as simple rows (name, price, rating), or the "No results"
/// line. The section tasks replace it with purpose-built views.
public struct GenericSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    /// The first array under the common list keys, else any array of objects.
    static func items(in data: JSONValue) -> [SectionItem] {
        for key in ["results", "items", "options", "plans", "activities", "places", "tours", "events"] {
            if let array = data[key].array, !array.isEmpty { return array.map(SectionItem.init) }
        }
        for (_, value) in (data.object ?? [:]).sorted(by: { $0.key < $1.key }) {
            if let array = value.array, array.contains(where: { $0.object != nil }) { return array.map(SectionItem.init) }
        }
        return []
    }

    public var body: some View {
        let rows = Self.items(in: data)
        if rows.isEmpty {
            Text(verbatim: L10n.text(K.sections.page.noResults))
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.textMuted)
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                    VCard {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            if let name = item.name {
                                Text(verbatim: name)
                                    .font(VFont.body(.subheadline, weight: .semibold))
                                    .foregroundStyle(SemanticColor.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if item.priceUSD != nil {
                                PriceText(amount: item.priceUSD, currency: "USD", estimate: item.isEstimate)
                            }
                            if let rating = item.rating {
                                Text(verbatim: "★ " + String(format: "%.1f", locale: LanguageController.current.intlLocale, rating))
                                    .font(VFont.body(.caption))
                                    .foregroundStyle(SemanticColor.textMuted)
                            }
                        }
                    }
                }
            }
        }
    }
}
