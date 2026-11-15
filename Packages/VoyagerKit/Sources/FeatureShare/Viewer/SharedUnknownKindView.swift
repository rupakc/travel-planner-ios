import DesignSystem
import L10n
import SharedUI
import SwiftUI

#if canImport(UIKit)
import SafariServices
#endif

/// A share whose kind this app does not show (a quiz result, a trip status, or a kind added later): the headline and
/// a way to read it on the web. Never fails and never guesses at fields.
struct SharedUnknownKindView: View {
    let headline: String
    let ownerName: String?
    /// The share's web page (https), nil when the app has no backend address to build it from.
    let browserURL: URL?
    @State private var browsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: headline)
                        .font(VFont.display(.title))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let ownerName {
                        Text(verbatim: L10n.text(K.share.page.byline, ["name": ownerName]))
                            .font(VFont.body(.footnote))
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
            if browserURL != nil {
                VButton(L10n.text(K.mobile.share.openInBrowser), tid: "share.openInBrowser", role: .primary, systemImage: "safari") {
                    browsing = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        #if canImport(UIKit)
        .sheet(isPresented: $browsing) {
            if let browserURL { SharePageBrowser(url: browserURL).ignoresSafeArea() }
        }
        #endif
    }
}

#if canImport(UIKit)
/// `SFSafariViewController` for the share's own web page.
private struct SharePageBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(SemanticColor.primary)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
