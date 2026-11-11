import DesignSystem
import L10n
import SwiftUI
import Telemetry

/// "Book" always means "open the provider's page" in `SFSafariViewController`: no in-app payment.
/// Only `https` URLs are shown; anything else renders nothing. Emits `link_out` with the host only.
public struct BookingLink: View {
    private let url: URL
    private let section: String
    private let tid: String
    @State private var presented = false
    @Environment(\.telemetryRoute) private var route

    public init(url: URL, section: String, tid: String) {
        self.url = url
        self.section = section
        self.tid = tid
    }

    /// `https` with a host.
    public static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host()?.isEmpty ?? true)
    }

    /// The host, lowercased: the only part of the URL that goes into telemetry.
    public static func domain(of url: URL) -> String? {
        url.host()?.lowercased()
    }

    public var body: some View {
        if Self.isAllowed(url), let domain = Self.domain(of: url) {
            Button {
                Telemetry.shared.track(.uiTap(tid: tid, route: route))
                Telemetry.shared.track(.linkOut(section: section, domain: domain))
                presented = true
            } label: {
                Label {
                    Text(verbatim: L10n.text(K.results.flights.book))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.up.right.square").accessibilityHidden(true)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier(tid)
            #if canImport(UIKit)
            .fullScreenCover(isPresented: $presented) {
                SafariView(url: url).ignoresSafeArea()
            }
            #endif
        }
    }
}
