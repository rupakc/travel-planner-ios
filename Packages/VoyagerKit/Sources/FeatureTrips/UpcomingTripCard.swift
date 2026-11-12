import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// The next trip, pinned at the top of the Trips tab.
struct UpcomingTripCard: View {
    let plan: PlanSummary
    let departure: Date?
    let onOpen: () -> Void
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: "trips.upcoming", route: route))
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: L10n.text(K.mobile.trips.nextTrip))
                    .font(VFont.body(.caption, weight: .semibold))
                    .foregroundStyle(SemanticColor.onPrimary.opacity(0.85))
                Text(verbatim: plan.name ?? plan.searchData["destination"].string ?? "")
                    .font(VFont.display(.title3))
                    .foregroundStyle(SemanticColor.onPrimary)
                    .multilineTextAlignment(.leading)
                if let departure {
                    Text(verbatim: L10n.text(K.mobile.trips.departs, ["date": Fmt.date(departure)]))
                        .font(VFont.body(.subheadline))
                        .foregroundStyle(SemanticColor.onPrimary.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            .background(SemanticColor.primary, in: RoundedRectangle(cornerRadius: Radius.largeCard))
            .contentShape(RoundedRectangle(cornerRadius: Radius.largeCard))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trips.upcoming")
    }
}
