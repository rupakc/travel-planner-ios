import SwiftUI
import VoyagerModel

/// Extension point on `WatchCard`, between the price details and the actions: the price story (Task 3.2). Without the
/// Alerts screen's story store (a preview) or on an older backend it shows nothing, so the card is unchanged.
/// The card (`WatchCard`) starts the load: a `.task` on this view would never run while the story is an `EmptyView`.
struct WatchCardSlot: View {
    let kind: WatchKind
    let watchID: Int
    @Environment(\.priceStories) private var stories

    var body: some View {
        if let stories {
            let model = stories.model(kind: kind, watchID: watchID)
            PriceStoryView(model: model)
        }
    }
}
