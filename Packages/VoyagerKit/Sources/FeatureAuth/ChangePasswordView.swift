import SharedUI
import SwiftUI
import VoyagerEnv

/// Entry view stub (Task 14). Task 17 replaces this file and keeps the signature.
public struct ChangePasswordView: View {
    let env: AppEnvironment
    let forced: Bool

    @MainActor public init(env: AppEnvironment, forced: Bool) {
        self.env = env
        self.forced = forced
    }

    public var body: some View {
        EmptyState(icon: "key", title: "Change password")
    }
}
