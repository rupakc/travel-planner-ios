import SwiftUI

public enum AdaptiveLayout {
    /// The widest a reading column gets on a regular-width screen.
    public static let readableMaxWidth: CGFloat = 720

    public static func isRegular(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular
    }
}

/// `compact` on iPhone and in narrow iPad windows (Split View, Slide Over), `regular` otherwise.
/// It follows the size class, not the device, so multitasking resizes switch layouts.
public struct AdaptiveColumns<Compact: View, Regular: View>: View {
    private let compact: Compact
    private let regular: Regular
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(@ViewBuilder compact: () -> Compact, @ViewBuilder regular: () -> Regular) {
        self.compact = compact()
        self.regular = regular()
    }

    public var body: some View {
        if AdaptiveLayout.isRegular(sizeClass) { regular } else { compact }
    }
}

private struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: AdaptiveLayout.isRegular(sizeClass) ? AdaptiveLayout.readableMaxWidth : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Caps the width at 720 pt in regular size class and centres the column; full width in compact.
    public func readableWidth() -> some View {
        modifier(ReadableWidth())
    }
}
