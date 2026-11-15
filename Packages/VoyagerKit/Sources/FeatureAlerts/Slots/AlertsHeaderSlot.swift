import DesignSystem
import SwiftUI

/// Extension point under the Alerts intro text: the savings header and the paused banner (Task 3.3); Task 3.4 adds the
/// suggestions and prefs entry points. Shows nothing on a backend without Alerts 2.0, so the page is unchanged.
struct AlertsHeaderSlot: View {
    let model: AlertsHeaderModel

    var body: some View {
        if model.isAvailable {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if model.showsPausedBanner { PausedBanner() }
                SavingsHeader(model: model)
            }
        }
    }
}
