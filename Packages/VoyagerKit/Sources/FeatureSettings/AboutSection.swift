import DesignSystem
import L10n
import SharedUI
import SwiftUI

struct AboutSection: View {
    let model: SettingsModel
    static let licenceURL = URL(string: "https://github.com/rupakc/travel-planner-ios/blob/main/LICENSE")!

    var body: some View {
        SettingsGroup(title: L10n.text(K.mobile.settings.about)) {
            Text(verbatim: L10n.text(K.mobile.settings.version, ["version": model.env.build.appVersion]))
                .font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                .accessibilityIdentifier("settings.version")
            Link(destination: Self.licenceURL) {
                HStack {
                    Text(verbatim: L10n.text(K.mobile.settings.licences)).font(VFont.body(.body))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.footnote).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
            .tint(SemanticColor.primary)
            .accessibilityIdentifier("settings.licences")
            AttributionFooter()
        }
    }
}
