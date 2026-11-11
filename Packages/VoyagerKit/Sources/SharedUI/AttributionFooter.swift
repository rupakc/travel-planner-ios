import DesignSystem
import L10n
import SwiftUI

/// The mandatory GeoNames (CC BY 4.0) and OurAirports attribution, from the web's `common:footer.attribution`.
public struct AttributionFooter: View {
    public init() {}

    static let links: [String: URL] = [
        "geonames": URL(string: "https://www.geonames.org")!,
        "licence": URL(string: "https://creativecommons.org/licenses/by/4.0/")!,
        "ourairports": URL(string: "https://ourairports.com")!,
    ]

    public var body: some View {
        Text(L10n.attributed(K.common.footer.attribution, links: Self.links))
            .font(VFont.body(.caption))
            .foregroundStyle(SemanticColor.textMuted)
            .tint(SemanticColor.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity)
    }
}
