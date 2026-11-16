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

    private var singleLine: some View {
        HStack(spacing: Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(verbatim: title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
    }

    /// The icon flows inline with the text, so wrapped lines and icon centre together as one group.
    private var wrapped: some View {
        let label = Text(verbatim: title)
        let text = systemImage.map { Text(Image(systemName: $0)) + Text(verbatim: " ") + label } ?? label
        return text
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    public var body: some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: tid, route: route))
            action()
        } label: {
            // A single line at the user's size when it fits; else a single line at a smaller Dynamic Type
            // size (so a long word never breaks mid-word); only then wrapped, capped at AX1 and scaled down
            // rather than broken. The icon and label are one centred group in every variant.
            ViewThatFits(in: .horizontal) {
                singleLine
                singleLine.dynamicTypeSize(...DynamicTypeSize.accessibility1)
                singleLine.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                wrapped.dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
