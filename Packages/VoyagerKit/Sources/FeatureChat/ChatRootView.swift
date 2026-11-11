import SharedUI
import SwiftUI
import VoyagerEnv

/// Entry view stub (Task 14). Task 31 replaces this file and keeps the signature.
public struct ChatRootView: View {
    let env: AppEnvironment

    @MainActor public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        EmptyState(icon: "bubble.left.and.bubble.right", title: "Chat")
    }
}
