import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Where a slot can go: every valid position (with the activity it would swap with) and "Remove from day".
struct MoveSheet: View {
    let name: String
    let targets: [JSONValue]
    let onMove: (Int, String) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                        if let day = target["day_number"].int, let tod = target["time_of_day"].string {
                            Button {
                                onMove(day, tod)
                                dismiss()
                            } label: {
                                Text(verbatim: Self.title(for: target))
                                    .font(VFont.body(.body))
                                    .foregroundStyle(SemanticColor.text)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("itinerary.move.target")
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Text(verbatim: L10n.text(K.itinerary.menu.removeFromDay))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("itinerary.move.remove")
                }
            }
            .navigationTitle(Text(verbatim: L10n.text(K.itinerary.aria.move, ["name": name])))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text(verbatim: L10n.text(K.itinerary.edit.done)) }
                        .accessibilityIdentifier("itinerary.move.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    static func swapSuffix(_ key: LKey, _ swapWith: JSONValue) -> String {
        guard let name = swapWith["activity"].string, !name.isEmpty else { return "" }
        return L10n.text(key, ["name": name])
    }

    static func title(for target: JSONValue) -> String {
        L10n.text(K.itinerary.menu.moveTo, [
            "position": ItineraryText.position(day: target["day_number"], timeOfDay: target["time_of_day"]),
            "swap": swapSuffix(K.itinerary.menu.swapWith, target["swapWith"]),
        ])
    }
}
