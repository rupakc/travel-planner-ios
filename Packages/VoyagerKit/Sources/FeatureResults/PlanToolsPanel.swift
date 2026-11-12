import SectionsUI
import SwiftUI
import VoyagerEnv

/// Plan tools above the sections (best-value package, budget planner, fare calendar, export). Task 25 owns this
/// file and replaces the body; the signature below is what `ResultsView` calls.
struct PlanToolsPanel: View {
    let env: AppEnvironment
    let state: ResultsState
    let ctx: SectionContext

    var body: some View { EmptyView() }
}
