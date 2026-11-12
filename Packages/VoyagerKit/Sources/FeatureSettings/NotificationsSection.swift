import L10n
import SwiftUI

struct NotificationsSection: View {
    let model: SettingsModel

    var body: some View {
        @Bindable var device = model.env.device
        SettingsGroup(title: L10n.text(K.mobile.settings.notifications)) {
            SettingsToggleRow(
                title: L10n.text(K.mobile.settings.reminders), hint: L10n.text(K.mobile.settings.remindersHint),
                tid: "settings.reminders", isOn: $device.reminderOptIn)
            SettingsToggleRow(
                title: L10n.text(K.mobile.settings.alertPoll), hint: L10n.text(K.mobile.settings.alertPollHint),
                tid: "settings.alertPoll", isOn: $device.alertPoll)
            SettingsToggleRow(
                title: L10n.text(K.mobile.settings.nearbyInvites), hint: L10n.text(K.mobile.settings.nearbyInvitesHint),
                tid: "settings.nearbyInvites", isOn: $device.nearbyInvites)
        }
    }
}
