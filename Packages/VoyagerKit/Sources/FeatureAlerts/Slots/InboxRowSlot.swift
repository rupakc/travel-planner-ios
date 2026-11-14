import SwiftUI
import VoyagerModel

/// Extension point inside an inbox row, under its text: Task 3.3 puts the drop moment and the digest summary here.
/// Empty until then, so the row is unchanged.
struct InboxRowSlot: View {
    let item: AppNotification

    var body: some View {
        EmptyView()
    }
}
