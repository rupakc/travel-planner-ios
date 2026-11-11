import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// Entry view stub (Task 14). Task 24 replaces this file and keeps the signature.
public struct ResultsView: View {
    let env: AppEnvironment
    let request: TravelSearchRequest

    @MainActor public init(env: AppEnvironment, request: TravelSearchRequest) {
        self.env = env
        self.request = request
    }

    public var body: some View {
        EmptyState(icon: "list.bullet.rectangle", title: "Results")
    }
}
