import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// SIM and eSIM plans, one selectable plan.
public struct SimSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let plans = data["plans"].array ?? []
        if plans.isEmpty {
            CommerceEmpty(text: L10n.text(K.results.sim.none))
        } else {
            CommerceRows(count: plans.count, layout: ctx.layout) { index in
                SimPlanRow(plan: plans[index], ctx: ctx)
            }
        }
    }
}
