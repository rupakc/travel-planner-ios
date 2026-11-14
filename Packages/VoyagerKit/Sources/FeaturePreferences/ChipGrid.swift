import DesignSystem
import SwiftUI

/// Chips in equal-width columns. A `Grid` (not a custom wrapping `Layout`) so the height it reports is always the
/// height it draws, in hosted snapshots too.
struct ChipGrid<Item, Content: View>: View {
    let items: [Item]
    var columns = 2
    var spacing: CGFloat = Spacing.sm
    @ViewBuilder let content: (Item) -> Content

    /// The items split into rows of `columns`.
    nonisolated static func rows(_ items: [Item], columns: Int) -> [[Item]] {
        let size = max(columns, 1)
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    var body: some View {
        let rows = Self.rows(items, columns: columns)
        Grid(alignment: .leading, horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(rows.indices, id: \.self) { index in
                GridRow {
                    ForEach(rows[index].indices, id: \.self) { column in
                        content(rows[index][column]).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
