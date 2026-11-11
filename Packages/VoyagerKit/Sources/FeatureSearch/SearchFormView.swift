import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// Entry view stub (Task 14). Task 20 replaces this file and keeps the signature.
public struct SearchFormView: View {
    let env: AppEnvironment
    let prefill: TravelSearchRequest?

    @MainActor public init(env: AppEnvironment, prefill: TravelSearchRequest?) {
        self.env = env
        self.prefill = prefill
    }

    public var body: some View {
        EmptyState(icon: "magnifyingglass", title: "Search")
    }
}
