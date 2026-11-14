import SwiftUI

#if canImport(UIKit)
import UIKit

/// The system share sheet (`UIActivityViewController`) for a link or a file. A file URL with an `.ics` extension
/// is shared as `text/calendar`.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
