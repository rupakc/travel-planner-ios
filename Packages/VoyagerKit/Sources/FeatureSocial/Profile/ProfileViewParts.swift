import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry

/// A row that opens another screen: title, optional trailing count, chevron.
struct ProfileLinkRow: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                .multilineTextAlignment(.leading)
            Spacer(minLength: Spacing.sm)
            if let detail {
                Text(verbatim: detail).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            }
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(SemanticColor.textMuted).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A switch with a label that wraps at word boundaries.
struct ProfileToggleRow: View {
    let title: String
    let tid: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
        }
        .tint(SemanticColor.primary)
        .telemetryToggle(tid: tid, value: isOn)
        .accessibilityIdentifier(tid)
    }
}

/// Two actions side by side when they fit, stacked when they do not (never a mid-word break).
struct ActionPair<A: View, B: View>: View {
    @ViewBuilder let first: A
    @ViewBuilder let second: B

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) { first; second }
            VStack(spacing: Spacing.sm) { first; second }
        }
    }
}

struct ProfileFailureView: View {
    let message: String
    let tid: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: message).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
            VButton(L10n.text(K.social.feed.retry), tid: tid, role: .secondary, action: retry)
        }
    }
}
