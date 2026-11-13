import L10n
import SwiftUI
import VoyagerModel

/// Edit one slot: activity, location, estimated cost (all into `itinerary_edits`) and a personal note
/// (`itinerary_notes`). Saves on Done.
struct SlotEditor: View {
    let initialActivity: String
    let initialLocation: String
    let initialCost: Double?
    let initialNote: String
    let onSave: (_ activity: String, _ location: String, _ cost: Double?, _ note: String) -> Void

    @State private var activity = ""
    @State private var location = ""
    @State private var cost = ""
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                field(K.itinerary.edit.activity, text: $activity, tid: "itinerary.edit.activity")
                field(K.itinerary.edit.location, text: $location, tid: "itinerary.edit.location")
                field(K.itinerary.edit.cost, text: $cost, tid: "itinerary.edit.cost")
                    .keyboardType(.decimalPad)
                Section {
                    TextField(
                        text: $note, axis: .vertical,
                        label: { Text(verbatim: L10n.text(K.itinerary.edit.notePlaceholder)) }
                    )
                    .lineLimit(2...6)
                    .accessibilityIdentifier("itinerary.edit.note")
                } header: {
                    Text(verbatim: L10n.text(K.itinerary.edit.note))
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(activity, location, ItineraryText.parseCost(cost), note)
                        dismiss()
                    } label: { Text(verbatim: L10n.text(K.itinerary.edit.done)) }
                    .accessibilityIdentifier("itinerary.edit.done")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            activity = initialActivity
            location = initialLocation
            cost = initialCost.map(Self.editText) ?? ""
            note = initialNote
        }
    }

    /// Plain digits with no grouping, so what is shown parses back (`12`, `12.5`).
    static func editText(_ cost: Double) -> String {
        if let whole = Int(exactly: cost) { return String(whole) }
        return String(cost)
    }

    private func field(_ label: LKey, text: Binding<String>, tid: String) -> some View {
        Section {
            TextField(text: text, label: { Text(verbatim: L10n.text(label)) })
                .accessibilityIdentifier(tid)
        } header: {
            Text(verbatim: L10n.text(label))
        }
    }
}
