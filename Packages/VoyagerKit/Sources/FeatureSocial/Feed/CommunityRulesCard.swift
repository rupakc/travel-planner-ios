import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// The community rules, shown once per user before their first public post (plan ruling R13): "I agree" remembers it on
/// this device and continues the action, Cancel stops it.
struct CommunityRulesCard: View {
    let tidPrefix: String
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.mobile.rules.title))
                    .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: L10n.text(K.mobile.rules.body))
                    .font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                ActionPair {
                    VButton(L10n.text(K.social.actions.cancel), tid: "\(tidPrefix).rules.cancel", role: .secondary, action: decline)
                } second: {
                    VButton(L10n.text(K.mobile.rules.accept), tid: "\(tidPrefix).rules.accept", action: accept)
                }
            }
        }
        .accessibilityIdentifier("\(tidPrefix).rules")
    }
}
