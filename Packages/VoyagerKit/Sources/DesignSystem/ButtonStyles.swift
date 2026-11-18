import SwiftUI

/// Shared look of the four button styles: 44 pt minimum height, Inter semibold. The shape is a rounded rectangle
/// whose radius is fixed at half the minimum height: exactly a pill for one line, and a rounded rectangle (not a
/// giant oval) once a long label wraps at AX5.
private struct VButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let foreground: Color
    let background: Color
    let stroke: Color?
    @Environment(\.isEnabled) private var isEnabled

    private static let minHeight: CGFloat = 44
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.minHeight / 2, style: .circular) }

    var body: some View {
        configuration.label
            .font(VFont.body(.headline, weight: .semibold))
            .foregroundStyle(isEnabled ? foreground : SemanticColor.disabledText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .frame(minHeight: Self.minHeight)
            .frame(maxWidth: .infinity)
            .borderedSurface(shape, fill: isEnabled ? background : SemanticColor.disabledFill, border: isEnabled ? stroke : nil)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 1)
            .contentShape(shape)
    }
}

public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        VButtonBody(
            configuration: configuration, foreground: SemanticColor.onPrimary,
            background: SemanticColor.primary, stroke: nil)
    }
}

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        VButtonBody(
            configuration: configuration, foreground: SemanticColor.primary,
            background: SemanticColor.surfaceRaised, stroke: SemanticColor.border)
    }
}

public struct TonalButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        VButtonBody(
            configuration: configuration, foreground: SemanticColor.text,
            background: Palette.color(.gray, .s100), stroke: nil)
    }
}

public struct DestructiveButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        // The danger family's tinted pairing (100 fill, 800 label, 200 edge): readable in both schemes, unlike white on the
        // light coral that red-600 becomes in dark.
        VButtonBody(
            configuration: configuration, foreground: Palette.color(.red, .s800),
            background: Palette.color(.red, .s100), stroke: Palette.color(.red, .s200))
    }
}
