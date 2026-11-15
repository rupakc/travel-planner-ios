import DesignSystem
import L10n
import SwiftUI
import VoyagerModel

/// One suggested watch: a tick, what it is, why it is suggested, and where its watch stands.
struct SuggestionRow: View {
    let row: SuggestionsModel.Row
    let isLocked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: marker.symbol)
                    .font(.title3)
                    .foregroundStyle(marker.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: row.suggestion.title)
                        .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                        .multilineTextAlignment(.leading)
                    if let subtitle = row.suggestion.subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                    if let reason = SuggestionsModel.reasonText(row.suggestion.reason) {
                        Text(verbatim: reason).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                    if let status = statusText {
                        Text(verbatim: status.text)
                            .font(VFont.body(.caption, weight: .semibold))
                            .foregroundStyle(status.isError ? SemanticColor.destructive : SemanticColor.text)
                            .multilineTextAlignment(.leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that washes out the status line, which is the part a failed row needs readable.
        .allowsHitTesting(!(isLocked || row.status != .idle))
        .opacity(row.status == .already ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.selected && row.status == .idle ? .isSelected : [])
        .accessibilityIdentifier("suggestions.row.\(row.id)")
    }

    /// The tick follows the row's outcome: ticked to watch, done, already watched, failed.
    private var marker: (symbol: String, color: Color) {
        switch row.status {
        case .idle:
            row.selected
                ? ("checkmark.circle.fill", SemanticColor.primary) : ("circle", SemanticColor.textMuted)
        case .running: ("circle.dotted", SemanticColor.textMuted)
        case .done: ("checkmark.circle.fill", SemanticColor.primary)
        case .already: ("checkmark.circle", SemanticColor.textMuted)
        case .failed: ("exclamationmark.circle", SemanticColor.destructive)
        }
    }

    private var statusText: (text: String, isError: Bool)? {
        switch row.status {
        case .idle: nil
        case .running: (L10n.text(K.watchSuggest.status.running), false)
        case .done: (L10n.text(K.watchSuggest.status.done), false)
        case .already: (L10n.text(K.watchSuggest.status.already), false)
        case .failed(let message): (message, true)
        }
    }
}
