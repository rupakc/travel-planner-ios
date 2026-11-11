import SharedUI
import SwiftUI
import VoyagerEnv

/// Entry view stub (Task 14). Task 19 replaces this file and keeps the signature.
public struct PlanDetailView: View {
    let env: AppEnvironment
    let planID: Int

    @MainActor public init(env: AppEnvironment, planID: Int) {
        self.env = env
        self.planID = planID
    }

    public var body: some View {
        EmptyState(icon: "doc.text", title: "Plan")
    }
}
