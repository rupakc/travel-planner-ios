import SwiftUI
import VoyagerModel

/// Extension point inside an inbox row, under its text: the drop moment of a drop notification and the summary of the
/// weekly digest (Task 3.3). Every other row, and a row with no inbox around it (a preview), is unchanged.
struct InboxRowSlot: View {
    let item: AppNotification
    @Environment(\.inboxExtras) private var extras

    var body: some View {
        if let extras {
            if let content = extras.dropContent(for: item) {
                DropMomentCard(content: content)
                    .onAppear { extras.dropSeen(item) }
            } else if item.isPriceDigest, let digest = item.digest {
                DigestRow(digest: digest)
            }
        }
    }
}
