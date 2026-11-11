import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// One result section: accent header (title, verification chip, status), collapsible body. Body shows a
/// skeleton while loading, the unavailable copy on error, otherwise `content`. A `waiting` section is hidden.
public struct SectionCard<Content: View>: View {
    private let id: SectionID
    private let status: SectionStatus
    private let verification: JSONValue?
    private let expanded: Binding<Bool>
    private let content: Content
    @Environment(\.telemetryRoute) private var route

    public init(
        id: SectionID,
        status: SectionStatus,
        verification: JSONValue? = nil,
        expanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.status = status
        self.verification = verification
        self.expanded = expanded
        self.content = content()
    }

    public var body: some View {
        if status.isVisible {
            VStack(alignment: .leading, spacing: 0) {
                header
                if expanded.wrappedValue {
                    Divider().overlay(SemanticColor.border)
                    bodyContent
                        .padding(Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(SemanticColor.surfaceRaised)
            .overlay(alignment: .leading) {
                Rectangle().fill(SectionAccent.color(for: id.rawValue)).frame(width: 4)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.itemCard))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("results.section.\(id.rawValue)")
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                let opening = !expanded.wrappedValue
                expanded.wrappedValue = opening
                Telemetry.shared.track(.uiTap(tid: "results.section.toggle", route: route))
                if opening { Telemetry.shared.track(.sectionExpand(section: id.rawValue)) }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: id.symbol)
                        .foregroundStyle(SectionAccent.color(for: id.rawValue))
                        .accessibilityHidden(true)
                    Text(verbatim: id.title)
                        .font(VFont.display(.headline))
                        .foregroundStyle(SemanticColor.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.xs)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("results.section.toggle")
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(
                L10n.text(expanded.wrappedValue ? K.sections.card.expanded : K.sections.card.collapsed))
            if let verification, status.isReady { VerificationBadge(verification: verification) }
            statusView
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SemanticColor.textMuted)
                .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
                .accessibilityHidden(true)
        }
        .padding(.leading, Spacing.lg)
        .padding(.trailing, Spacing.md)
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .loading:
            ProgressView().controlSize(.small).accessibilityLabel(L10n.text(K.results.loading.default))
        case .enhancing:
            HStack(spacing: Spacing.xs) {
                ProgressView().controlSize(.mini)
                Text(verbatim: L10n.text(K.results.status.enhancing))
                    .font(VFont.body(.caption, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Palette.color(.amber, .s700))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Palette.color(.amber, .s100), in: Capsule())
            .overlay { Capsule().strokeBorder(Palette.color(.amber, .s200), lineWidth: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityHint(L10n.text(K.results.status.enhancingTitle))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.color(.teal, .s600).opacity(0.7))
                .accessibilityHidden(true)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SemanticColor.destructive)
                .accessibilityHidden(true)
        case .waiting:
            EmptyView()
        }
    }

    @ViewBuilder private var bodyContent: some View {
        switch status {
        case .loading:
            Skeleton()
        case .error(let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(verbatim: detail.isEmpty ? L10n.text(id.unavailableKey) : detail)
                .font(VFont.body(.subheadline))
                .foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        default:
            content
        }
    }
}
