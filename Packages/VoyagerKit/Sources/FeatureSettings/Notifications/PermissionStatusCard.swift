import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The iOS permission as Settings shows it: nothing while allowed, the system prompt while it was never asked, and an
/// honest "turned off" note with "Open Settings" once it was refused (iOS asks only once).
struct PermissionStatusCard: View {
    let state: NotificationPermissionState
    let allow: () -> Void
    let openSettings: () -> Void

    var body: some View {
        switch state {
        case .notDetermined:
            card {
                Text(verbatim: L10n.text(K.mobile.permissions.notificationsTitle))
                    .font(VFont.body(.headline)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: L10n.text(K.mobile.permissions.notificationsBody))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                VButton(L10n.text(K.mobile.permissions.allow), tid: "notifications.permission.allow", action: allow)
            }
        case .denied:
            card {
                Label {
                    Text(verbatim: L10n.text(K.mobile.notifSettings.permissionDenied))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "bell.slash").foregroundStyle(SemanticColor.destructive)
                }
                VButton(
                    L10n.text(K.mobile.permissions.openSettings), tid: "notifications.permission.openSettings",
                    role: .secondary, action: openSettings)
            }
        case .allowed, .unknown:
            EmptyView()
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) { content() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notifications.permission")
    }
}
