import SwiftUI

/// Shared look of the four button styles: 44 pt minimum height, pill shape, Inter semibold.
private struct VButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let foreground: Color
    let background: Color
    let stroke: Color?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(VFont.body(.headline, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .borderedSurface(Capsule(), fill: background, border: stroke)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(Capsule())
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
        VButtonBody(
            configuration: configuration, foreground: SemanticColor.onPrimary,
            background: SemanticColor.destructive, stroke: nil)
    }
}
