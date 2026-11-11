import SharedUI
import SwiftUI
import VoyagerEnv

/// Entry view stub (Task 14). Task 21 replaces this file and keeps the signature.
public struct DiscoverView: View {
    let env: AppEnvironment

    @MainActor public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        EmptyState(icon: "dice", title: "Discover")
    }
}
