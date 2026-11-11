import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// Entry view stub (Task 14). Task 32 replaces this file and keeps the signature.
public struct AlertsRootView: View {
    let env: AppEnvironment
    let kind: WatchKind?
    let watchID: Int?

    @MainActor public init(env: AppEnvironment, kind: WatchKind?, watchID: Int?) {
        self.env = env
        self.kind = kind
        self.watchID = watchID
    }

    public var body: some View {
        EmptyState(icon: "bell", title: "Alerts")
    }
}
