import L10n
import SwiftUI

struct PrivacySection: View {
    let model: SettingsModel

    var body: some View {
        SettingsGroup(title: L10n.text(K.privacy.section.privacy)) {
            SettingsToggleRow(
                title: L10n.text(K.privacy.switch.label), hint: L10n.text(K.privacy.switch.hint), tid: "privacy.switch",
                isOn: Binding(get: { model.telemetryOn }, set: { model.setTelemetry($0) }))
            SettingsLinkRow(
                title: L10n.text(K.privacy.choices), icon: "hand.raised", tid: "privacy.choices"
            ) { model.reopenConsent() }
        }
    }
}
