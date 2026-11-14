import DesignSystem
import SharedUI
import SwiftUI
import Telemetry

/// The look of My Plan's action buttons: icon and title scale together and the title wraps at word boundaries
/// inside a rounded rectangle with vertical padding (a pill would clip a wrapped title at large text sizes).
struct PlanActionLabel: View {
    enum Style { case primary, tonal, outline }

    let title: String
    let systemImage: String
    let style: Style

    @Environment(\.isEnabled) private var isEnabled

    private var foreground: Color {
        switch style {
        case .primary: SemanticColor.onPrimary
        case .tonal, .outline: SemanticColor.text
        }
    }

    private var fill: Color {
        switch style {
        case .primary: SemanticColor.primary
        case .tonal: Palette.color(.gray, .s100)
        case .outline: SemanticColor.surfaceRaised
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: systemImage).accessibilityHidden(true)
            Text(verbatim: title).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .font(VFont.body(.headline, weight: .semibold))
        .foregroundStyle(isEnabled ? foreground : SemanticColor.disabledText)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 44)
        .borderedSurface(
            RoundedRectangle(cornerRadius: Radius.largeCard), fill: isEnabled ? fill : SemanticColor.disabledFill,
            border: isEnabled && style == .outline ? SemanticColor.border : nil)
        .contentShape(RoundedRectangle(cornerRadius: Radius.largeCard))
    }
}

struct PlanActionButton: View {
    let title: String
    let systemImage: String
    let tid: String
    var style: PlanActionLabel.Style = .primary
    let action: () -> Void
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: tid, route: route))
            action()
        } label: {
            PlanActionLabel(title: title, systemImage: systemImage, style: style)
        }
        .buttonStyle(UndimmedButtonStyle())
        .accessibilityIdentifier(tid)
    }
}

/// Like `.plain` but without the system's extra dimming of a disabled button (the label draws its own disabled look).
private struct UndimmedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.85 : 1)
    }
}
