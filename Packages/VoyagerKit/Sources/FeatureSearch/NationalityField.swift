import L10n
import SwiftUI
import VoyagerModel

/// Nationality typeahead (`repos.reference.nationalities`).
struct NationalityField: View {
    let model: SearchFormModel

    var body: some View {
        SuggestionField(
            label: L10n.text(K.search.form.nationality),
            placeholder: L10n.text(K.search.form.nationalityPlaceholder),
            tid: "search.nationality",
            field: model.nationality,
            capitalization: .words,
            title: { $0.nationality ?? $0.country ?? "" },
            subtitle: { $0.nationality == nil ? nil : $0.country },
            onPick: { model.pick($0) })
    }
}
