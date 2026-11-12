import DesignSystem
import SectionsUI
import SwiftUI

/// iPad detail column: the selected section, full width, always expanded.
struct SectionDetailColumn: View {
    let state: ResultsState
    let selected: SectionID?
    let ctx: SectionContext

    var body: some View {
        if let selected, let entry = state.sections[selected], state.visibleSections.contains(selected) {
            ResultsSectionCard(id: selected, entry: entry, ctx: ctx, expanded: .constant(true))
                .accessibilityIdentifier("results.detail")
        } else {
            Color.clear.frame(height: 1)
        }
    }
}
