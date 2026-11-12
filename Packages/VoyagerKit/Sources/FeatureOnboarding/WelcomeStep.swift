import L10n
import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        StepScaffold(
            icon: "airplane.departure",
            title: L10n.text(K.onboarding.steps.welcome.title),
            message: L10n.text(K.onboarding.steps.welcome.body)
        ) { EmptyView() }
    }
}
