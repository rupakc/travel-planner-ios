import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// A labelled text field with a typeahead list underneath (airports, nationalities).
struct SuggestionField<Item: Sendable & Hashable>: View {
    let label: String?
    let placeholder: String
    let tid: String
    let field: Typeahead<Item>
    let capitalization: TextInputAutocapitalization
    let title: (Item) -> String
    let subtitle: (Item) -> String?
    let onPick: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let label {
                Text(verbatim: label)
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
            }
            HStack(spacing: 0) {
                TextField(placeholder, text: Binding(get: { field.text }, set: { field.edit($0) }))
                    .font(VFont.body(.body))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(capitalization)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(tid)
                if !field.text.isEmpty {
                    Button { field.clear() } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }
                    .foregroundStyle(SemanticColor.textMuted)
                    .accessibilityLabel(L10n.text(K.search.airport.clear))
                    .accessibilityIdentifier("\(tid).clear")
                }
            }
            .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(SemanticColor.border, lineWidth: 1) }
            if !field.isChosen, !field.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(field.suggestions.enumerated()), id: \.offset) { index, item in
                        Button { onPick(item) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: title(item))
                                    .font(VFont.body(.body))
                                    .foregroundStyle(SemanticColor.text)
                                if let sub = subtitle(item), !sub.isEmpty {
                                    Text(verbatim: sub)
                                        .font(VFont.body(.footnote))
                                        .foregroundStyle(SemanticColor.textMuted)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, Spacing.md)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(tid).suggestion.\(index)")
                        if index < field.suggestions.count - 1 { Divider() }
                    }
                }
                .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(SemanticColor.border, lineWidth: 1) }
            }
        }
    }
}

/// City or airport typeahead (`repos.reference.airports`, 250 ms debounce).
struct AirportField: View {
    let model: SearchFormModel
    let field: Typeahead<AirportSuggestion>
    let label: String?
    let tid: String

    var body: some View {
        SuggestionField(
            label: label,
            placeholder: L10n.text(K.search.form.cityOrAirport),
            tid: tid,
            field: field,
            capitalization: .words,
            title: { SearchFormModel.label($0) },
            subtitle: { airport in airport.name },
            onPick: { model.pick($0, into: field) })
    }
}
