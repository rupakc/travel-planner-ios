import DesignSystem
import L10n
import SwiftUI

/// "Contact support" (plan ruling R13, App Store 1.2). The owner supplies the URL; the row is absent while it is empty.
struct SupportRow: View {
    let url: URL?

    var body: some View {
        if let url {
            Link(destination: url) {
                Label(L10n.text(K.mobile.support.contact), systemImage: "lifepreserver")
                    .font(VFont.body(.footnote, weight: .medium))
                    .foregroundStyle(SemanticColor.primary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("social.support")
        }
    }
}
