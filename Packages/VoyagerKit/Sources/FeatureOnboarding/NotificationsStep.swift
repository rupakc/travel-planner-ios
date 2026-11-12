import L10n
import SwiftUI

/// The contextual ask: the system prompt appears only after the "Allow" button.
struct NotificationsStep: View {
    var body: some View {
        StepScaffold(
            icon: "bell.badge",
            title: L10n.text(K.onboarding.steps.notifications.title),
            message: L10n.text(K.mobile.permissions.notificationsBody)
        ) { EmptyView() }
    }
}
