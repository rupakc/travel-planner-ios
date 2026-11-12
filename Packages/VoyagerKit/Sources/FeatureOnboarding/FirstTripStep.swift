import L10n
import SwiftUI

struct FirstTripStep: View {
    var body: some View {
        StepScaffold(
            icon: "map",
            title: L10n.text(K.onboarding.steps.firstTrip.title),
            message: L10n.text(K.onboarding.steps.firstTrip.body)
        ) { EmptyView() }
    }
}
