import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry

/// The telemetry consent prompt for EU, EEA, UK and Swiss time zones: a non-modal card at the bottom,
/// shown once until the user chooses. It never blocks input above it.
enum ConsentPrompt {
    /// Shown when there is no choice yet and the time zone requires one.
    static func shouldShow(choice: ConsentChoice?, timeZone: String) -> Bool {
        choice == nil && Consent.required(timeZone: timeZone)
    }
}

struct ConsentCard: View {
    let telemetry: Telemetry
    @State private var answered = false

    var body: some View {
        if !answered && telemetry.requiresConsentPrompt {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.privacy.prompt.title))
                    .font(VFont.display(.headline))
                    .foregroundStyle(SemanticColor.text)
                Text(verbatim: L10n.text(K.privacy.prompt.body))
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.md) {
                    VButton(L10n.text(K.privacy.prompt.deny), tid: "privacy.deny", role: .secondary) { choose(false) }
                    VButton(L10n.text(K.privacy.prompt.allow), tid: "privacy.allow") { choose(true) }
                }
            }
            .padding(Spacing.lg)
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.largeCard))
            .overlay { RoundedRectangle(cornerRadius: Radius.largeCard).strokeBorder(SemanticColor.border, lineWidth: 1) }
            .shadow(radius: 8, y: 2)
            .padding(Spacing.lg)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("privacy.card")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func choose(_ granted: Bool) {
        telemetry.setConsent(granted)
        withAnimation { answered = true }
    }
}
