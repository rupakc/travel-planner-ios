import DesignSystem
import Domain
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// Plan tools above the sections once the search is done: remix, best-value package, budget planner.
/// The signature below is what `ResultsView` calls.
struct PlanToolsPanel: View {
    let env: AppEnvironment
    let state: ResultsState
    let ctx: SectionContext

    @State private var box = ToolsBox()

    @MainActor init(env: AppEnvironment, state: ResultsState, ctx: SectionContext) {
        self.env = env
        self.state = state
        self.ctx = ctx
    }

    var body: some View {
        Group {
            if state.done, state.readyCount > 0 { content(box.model(env: env)) }
        }
        .onDisappear { box.existing?.cancel() }
    }

    @ViewBuilder private func content(_ tools: PlanToolsModel) -> some View {
        let results = state.latestResults
        let searchData = state.searchData ?? env.plan.searchData
        let computed = tools.fit(searchData: searchData, results: results)
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if !tools.baselineDismissed, let baseline = RemixBaselines.baseline(for: searchData) {
                RemixDiffBanner(baseline: baseline, results: results) {
                    tools.baselineDismissed = true
                    RemixBaselines.clear(for: searchData)
                }
            }
            RemixMenu(searchData: searchData) { preset in
                tools.remix(preset, searchData: searchData, results: results)
            }
            if let pkg = tools.package(results: results, searchData: searchData, fit: computed?.1) {
                BestValueCard(
                    pkg: pkg, selections: env.plan.selections,
                    canUndo: tools.undoSelections != nil, onApply: { tools.applyPackage(pkg) }, onUndo: { tools.undoPackage() })
            }
            if let (allocation, fit) = computed {
                BudgetPlannerView(
                    allocation: allocation, fit: fit, cheaper: tools.cheaper, ctx: ctx,
                    onChange: { tools.change($0, to: $1, searchData: searchData, results: results) },
                    onTotal: { tools.setTotal($0, searchData: searchData, results: results) },
                    onReset: { tools.resetBudget() },
                    onFindCheaper: { tools.findCheaperHotels(maxNightly: $0, searchData: searchData) })
            }
        }
        .toast(Binding(get: { tools.toast }, set: { tools.toast = $0 }))
        .accessibilityIdentifier("results.planTools")
    }
}

/// Holds the tools model, created on first use (a `State` initial value would build a throwaway on every re-render).
@MainActor
final class ToolsBox {
    private(set) var existing: PlanToolsModel?

    func model(env: AppEnvironment) -> PlanToolsModel {
        if let existing { return existing }
        let made = PlanToolsModel(env: env)
        existing = made
        return made
    }
}
