import SwiftUI

extension View {
    /// `shape` filled with `fill` and, when given, a 1 pt `border` inside its edge.
    ///
    /// The border is a second fill under an inset fill, not `strokeBorder`: stroking a capsule (or a rounded
    /// rectangle whose radius is half its height) runs through a zero-length straight edge, which the renderer
    /// draws as a short vertical tick just outside the left and right ends of the pill.
    public func borderedSurface<S: InsettableShape>(_ shape: S, fill: Color, border: Color?) -> some View {
        background {
            if let border {
                shape.fill(border).overlay { shape.inset(by: 1).fill(fill) }
            } else {
                shape.fill(fill)
            }
        }
    }
}
