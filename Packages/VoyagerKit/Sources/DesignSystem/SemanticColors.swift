import SwiftUI

/// App-level colours. The asset catalog's dark appearance is already the web's dark remap
/// (`dark` in tokens.json: 600 in dark is the light teal-400 range), so one family/stop
/// resolves to the right tone in both schemes.
public enum SemanticColor {
    public static let surface = Palette.color(.gray, .s50)
    public static let surfaceRaised = Palette.white
    public static let text = Palette.color(.gray, .s900)
    public static let textMuted = Palette.color(.gray, .s500)
    public static let border = Palette.color(.gray, .s200)
    public static let accent = Palette.color(.accent, .s500)
    /// primary-600 in light; in dark the same token's dark appearance (the Android teal-400 role).
    public static let primary = Palette.color(.primary, .s600)
    /// Text and icons on `primary`.
    public static let onPrimary = Palette.white
    public static let destructive = Palette.color(.red, .s600)
}
