import SharedUI
import SwiftUI
import VoyagerEnv

/// Entry view stub (Task 14). Task 30 replaces this file and keeps the signature.
public struct SharedPlanView: View {
    let env: AppEnvironment
    let token: String

    @MainActor public init(env: AppEnvironment, token: String) {
        self.env = env
        self.token = token
    }

    public var body: some View {
        EmptyState(icon: "square.and.arrow.up", title: "Shared plan")
    }
}
