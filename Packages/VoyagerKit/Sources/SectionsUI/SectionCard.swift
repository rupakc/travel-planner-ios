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
            .background { accentedBackground }
            .clipShape(RoundedRectangle(cornerRadius: Radius.itemCard))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.itemCard).strokeBorder(SemanticColor.border, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("results.section.\(id.rawValue)")
        }
    }

    /// Raised surface with a 4 pt accent edge that follows the corner curve (the web's curved left border): the
    /// accent fills the card shape, masked to its left end, and the surface covers all but the leading 4 pt.
    private var accentedBackground: some View {
        let radius = Radius.itemCard
        return ZStack {
            RoundedRectangle(cornerRadius: radius).fill(SemanticColor.surfaceRaised)
            RoundedRectangle(cornerRadius: radius).fill(SectionAccent.color(for: id.rawValue))
                .mask(alignment: .leading) { Rectangle().frame(width: radius * 2) }
            RoundedRectangle(cornerRadius: radius).fill(SemanticColor.surfaceRaised)
                .padding(.leading, 4)
        }
        .accessibilityHidden(true)
    }

    private var header: some View {
        // One row when the title fits on a single line beside the chip; else the chip drops under the title.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                titleButton(singleLine: true)
                trailing
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                titleButton(singleLine: false)
                WrapLayout(spacing: Spacing.sm) { trailing }
            }
        }
        .padding(.leading, Spacing.lg)
        .padding(.trailing, Spacing.md)
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder private var trailing: some View {
        if let verification, status.isReady { VerificationBadge(verification: verification) }
        statusView
        chevron
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SemanticColor.textMuted)
            .rotationEffect(.degrees(expanded.wrappedValue ? 180 : 0))
            .accessibilityHidden(true)
    }

    private func titleButton(singleLine: Bool) -> some View {
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
                    .lineLimit(singleLine ? 1 : nil)
                    .fixedSize(horizontal: singleLine, vertical: true)
                    // A long word never breaks mid-word at the largest sizes: the title steps down a notch there.
                    .dynamicTypeSize(...(singleLine ? DynamicTypeSize.accessibility5 : DynamicTypeSize.accessibility2))
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
            .borderedSurface(Capsule(), fill: Palette.color(.amber, .s100), border: Palette.color(.amber, .s200))
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
