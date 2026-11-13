import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Rows in one column on iPhone (and narrow iPad windows), two on a regular-width screen. A plain stack and grid,
/// not lazy ones: a section holds at most a few dozen rows, and lazy containers stall hosted snapshots.
struct CommerceRows<Row: View>: View {
    let count: Int
    let layout: LayoutClass
    @ViewBuilder let row: (Int) -> Row

    var body: some View {
        if layout == .regular, count > 1 {
            Grid(horizontalSpacing: Spacing.sm, verticalSpacing: Spacing.sm) {
                ForEach(0..<((count + 1) / 2), id: \.self) { pair in
                    GridRow {
                        row(pair * 2)
                        if pair * 2 + 1 < count { row(pair * 2 + 1) } else { Color.clear.frame(height: 0) }
                    }
                }
            }
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(0..<count, id: \.self) { index in row(index) }
            }
        }
    }
}

/// The "Filters" button (with the number of active filters) and, when any are active, a Clear button.
struct FilterBar: View {
    let activeCount: Int
    let tidPrefix: String
    let onOpen: () -> Void
    let onClear: () -> Void
    let clearTitle: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) { buttons }
            VStack(alignment: .leading, spacing: Spacing.sm) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        let label = L10n.text(K.sections.page.filters) + (activeCount > 0 ? " (\(activeCount))" : "")
        VButton(
            label, tid: "\(tidPrefix).filters", role: activeCount > 0 ? .primary : .tonal,
            systemImage: "slider.horizontal.3", action: onOpen)
        if activeCount > 0 {
            VButton(clearTitle, tid: "\(tidPrefix).clear-filters", role: .secondary, systemImage: "xmark", action: onClear)
        }
    }
}

/// A filtered section's replacement data and the sheet that edits the filters. One per section view.
struct FilteredSection {
    var draft = FilterDraft()
    var override: JSONValue?
    var sheet = false
    var busy = false
    var failure: String?
}

/// The section's empty-state line.
struct CommerceEmpty: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(VFont.body(.subheadline))
            .foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
