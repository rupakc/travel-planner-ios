import SwiftUI

public enum VWeight: Sendable {
    case regular, medium, semibold, bold

    var postScriptName: String {
        switch self {
        case .regular: "Inter-Regular"
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold: "Inter-Bold"
        }
    }
}

/// Fonts that scale with Dynamic Type (`Font.custom(_:size:relativeTo:)`). Devanagari, Bengali and
/// Han glyphs fall back to the system fonts through CoreText's cascade.
public enum VFont {
    /// Sora, for headings.
    public static func display(_ style: Font.TextStyle) -> Font {
        let name = (style == .largeTitle || style == .title) ? "Sora-Bold" : "Sora-SemiBold"
        return .custom(name, size: baseSize(style), relativeTo: style)
    }

    /// Inter, for body text.
    public static func body(_ style: Font.TextStyle, weight: VWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: baseSize(style), relativeTo: style)
    }

    /// Point sizes at the default (Large) Dynamic Type setting.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}
