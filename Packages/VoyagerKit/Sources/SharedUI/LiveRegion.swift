import SwiftUI

/// Speaks a status change (a result arrived, a plan saved) to VoiceOver without moving focus.
@MainActor
public enum LiveRegion {
    public static func announce(_ text: String) {
        guard !text.isEmpty else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}
