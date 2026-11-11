import SharedUI
import SwiftUI
import VoyagerEnv

/// How the onboarding ended.
public enum OnboardingOutcome: Sendable, Equatable {
    case completed, skipped
}

/// Entry view stub (Task 14). Task 18 replaces this file and keeps the signature.
public struct OnboardingView: View {
    let env: AppEnvironment
    let fromSettings: Bool
    let onFinish: @MainActor (OnboardingOutcome) -> Void

    @MainActor public init(env: AppEnvironment, fromSettings: Bool, onFinish: @escaping @MainActor (OnboardingOutcome) -> Void) {
        self.env = env
        self.fromSettings = fromSettings
        self.onFinish = onFinish
    }

    public var body: some View {
        EmptyState(icon: "sparkles", title: "Onboarding")
    }
}
