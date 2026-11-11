import SwiftUI

public enum Motion {
    /// The standard transition curve; `nil` (no animation) when Reduce Motion is on.
    public static func standard(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }
}
