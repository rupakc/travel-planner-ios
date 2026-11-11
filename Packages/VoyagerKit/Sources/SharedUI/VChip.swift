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
                .background(selected ? SemanticColor.primary : SemanticColor.surfaceRaised, in: Capsule())
                .overlay { Capsule().strokeBorder(selected ? Color.clear : SemanticColor.border, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(tid)
    }
}
