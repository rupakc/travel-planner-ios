import L10n
import SwiftUI
import VoyagerModel

/// A trip recap share (`kind: recap`).
struct SharedRecapView: View {
    let card: SharedCard
    let fallbackHeadline: String
    let ownerName: String?
    let onPlanOwn: () -> Void

    var body: some View {
        SharedCardBody(
            tag: K.mobile.share.recapTag, headline: card.headline.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackHeadline,
            card: card, ownerName: ownerName, onPlanOwn: onPlanOwn)
    }
}
