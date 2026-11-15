import DesignSystem
import SwiftUI
import VoyagerModel

/// The leading icon of an inbox row that is not a price alert (price rows keep their look): trip phases, weather,
/// social and quiz rows get their own symbol, a grouped drop a stack, and a kind this app does not know a plain bell
/// (so a newer server's row still reads as a notification). Decorative: the row's text carries the meaning.
enum NotificationRowIcon {
    static func symbol(for item: AppNotification) -> String? {
        if let count = item.data["group_count"].int, count >= 2 { return "square.stack.fill" }
        guard let kind = item.kind else { return "bell" }
        switch kind {
        case "trip_t30", "trip_t7", "trip_t1": return "calendar.badge.clock"
        case "trip_morning": return "sun.max.fill"
        case _ where kind.hasPrefix("weather_"): return "cloud.sun.rain.fill"
        case _ where kind.hasPrefix("social_"): return "person.2.fill"
        case _ where kind.hasPrefix("quiz_"): return "questionmark.circle.fill"
        default: return NotificationCategory.of(kind: kind) == nil ? "bell" : nil
        }
    }
}

struct NotificationRowIconView: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(VFont.body(.title3))
            .foregroundStyle(SemanticColor.primary)
            .frame(width: 28)
            .accessibilityHidden(true)
    }
}
