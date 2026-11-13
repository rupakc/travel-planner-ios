import DesignSystem
import SwiftUI
import Telemetry

/// A selectable pill (filters, interests). 44 pt tall; the title wraps rather than truncates.
public struct VChip: View {
    private let title: String
    private let tid: String
    private let selected: Bool
    private let action: () -> Void
    @Environment(\.telemetryRoute) private var route

    public init(title: String, tid: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.tid = tid
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: tid, route: route))
            action()
        } label: {
            Text(verbatim: title)
                .font(VFont.body(.subheadline, weight: .medium))
                .foregroundStyle(selected ? SemanticColor.onPrimary : SemanticColor.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .borderedSurface(
                    Capsule(), fill: selected ? SemanticColor.primary : SemanticColor.surfaceRaised,
                    border: selected ? nil : SemanticColor.border)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(tid)
    }
}
