#if canImport(UIKit)
import DesignSystem
import SafariServices
import SwiftUI

/// `SFSafariViewController` for provider pages, tinted with the primary colour.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(SemanticColor.primary)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
