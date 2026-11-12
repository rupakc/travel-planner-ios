import DesignSystem
import SharedUI
import SwiftUI
import Telemetry

/// A titled card of rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: title)
                .font(VFont.display(.headline))
                .foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) { content }
            }
        }
    }
}

/// A tappable row with a trailing chevron.
struct SettingsLinkRow: View {
    let title: String
    let icon: String
    let tid: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon).foregroundStyle(SemanticColor.primary).accessibilityHidden(true)
                Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(SemanticColor.textMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tid)
    }
}

/// A switch with an optional hint under its label.
struct SettingsToggleRow: View {
    let title: String
    let hint: String?
    let tid: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                if let hint {
                    Text(verbatim: hint).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(SemanticColor.primary)
        .telemetryToggle(tid: tid, value: isOn)
        .accessibilityIdentifier(tid)
    }
}
