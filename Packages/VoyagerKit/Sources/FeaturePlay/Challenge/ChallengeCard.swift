import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The weekly challenge ("Know before you go"): five questions about the next trip's country (or a featured pack), once
/// a week. Whether it is done, and which country, are the server's words.
struct ChallengeCard: View {
    let challenge: PlayChallenge
    let busy: Bool
    let start: () -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.play.challenge.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: text).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if challenge.done {
                    Text(verbatim: L10n.text(K.play.challenge.done)).font(VFont.body(.body, weight: .semibold))
                        .foregroundStyle(SemanticColor.primary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("play.challenge.done")
                } else {
                    PlayButton(L10n.text(K.play.challenge.start), tid: "play.challenge.start", systemImage: "flag.checkered") {
                        start()
                    }
                    .disabled(busy)
                }
            }
        }
        .accessibilityIdentifier("play.challenge")
    }

    private var text: String {
        if challenge.kind == .destination, let country = challenge.country, !country.isEmpty {
            let name = country.count == 2 ? QuizText.regionName(code: country, fallback: country) : country
            return L10n.text(K.play.challenge.destination, ["country": name])
        }
        return L10n.text(K.play.challenge.featured)
    }
}
