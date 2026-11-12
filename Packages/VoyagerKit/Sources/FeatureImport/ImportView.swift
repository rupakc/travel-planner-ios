import Foundation
import SharedUI
import SwiftUI
import VoyagerEnv

/// Entry view stub (Task 14). Task 23 replaces this file and keeps the signature.
public struct ImportView: View {
    let env: AppEnvironment
    let initialURL: URL?

    @MainActor public init(env: AppEnvironment, initialURL: URL?) {
        self.env = env
        self.initialURL = initialURL
    }

    public var body: some View {
        EmptyState(icon: "link", title: "Import")
    }
}
