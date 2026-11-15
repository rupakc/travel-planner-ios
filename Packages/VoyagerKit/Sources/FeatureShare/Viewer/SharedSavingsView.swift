import L10n
import SwiftUI
import VoyagerModel

/// A price-alert savings share (`kind: savings`): "caught drops", never "saved".
struct SharedSavingsView: View {
    let card: SharedCard
    let fallbackHeadline: String
    let ownerName: String?
    let onPlanOwn: () -> Void

    var body: some View {
        SharedCardBody(
            tag: K.mobile.share.savingsTag, headline: card.headline.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackHeadline,
            card: card, ownerName: ownerName, onPlanOwn: onPlanOwn)
    }
}
