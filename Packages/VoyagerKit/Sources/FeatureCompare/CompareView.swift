import SharedUI
import SwiftUI
import VoyagerEnv

/// Entry view stub (Task 14). Task 22 replaces this file and keeps the signature.
public struct CompareView: View {
    let env: AppEnvironment

    @MainActor public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        EmptyState(icon: "square.split.2x1", title: "Compare")
    }
}
