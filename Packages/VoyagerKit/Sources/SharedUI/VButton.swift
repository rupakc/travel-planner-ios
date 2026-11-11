import DesignSystem
import SwiftUI
import Telemetry

public enum VButtonRole: Sendable {
    case primary, secondary, tonal, destructive
}

/// The app's button: emits `ui_tap` (tid + current route), then runs the action. `tid` is also the
/// accessibility identifier, so UI tests address controls by it. `title` is already localized.
public struct VButton: View {
    private let title: String
    private let tid: String
    private let role: VButtonRole
    private let systemImage: String?
    private let action: () -> Void
    @Environment(\.telemetryRoute) private var route

    public init(
        _ title: String,
        tid: String,
        role: VButtonRole = .primary,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.tid = tid
        self.role = role
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: tid, route: route))
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(role: role)
        .accessibilityIdentifier(tid)
    }
}

extension View {
    @ViewBuilder
    fileprivate func buttonStyle(role: VButtonRole) -> some View {
        switch role {
        case .primary: buttonStyle(PrimaryButtonStyle())
        case .secondary: buttonStyle(SecondaryButtonStyle())
        case .tonal: buttonStyle(TonalButtonStyle())
        case .destructive: buttonStyle(DestructiveButtonStyle())
        }
    }
}
