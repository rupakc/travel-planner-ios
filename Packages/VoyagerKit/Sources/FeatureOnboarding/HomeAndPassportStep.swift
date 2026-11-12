import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Step 3: home airport and passport, each a typeahead through the reference repository.
struct HomeAndPassportStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepScaffold(
            icon: "person.text.rectangle",
            title: L10n.text(K.onboarding.steps.homeAndPassport.title),
            message: L10n.text(K.onboarding.steps.homeAndPassport.body)
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                field(
                    label: L10n.text(K.search.form.flyingFrom),
                    placeholder: L10n.text(K.search.airport.placeholder),
                    chosen: model.homeAirport.map(Self.airportLabel),
                    text: $model.airportQuery,
                    clear: { model.clearAirport() },
                    tid: "onboarding.airport",
                    rows: {
                    ForEach(model.airportSuggestions, id: \.self) { airport in
                        suggestion(Self.airportLabel(airport), tid: "onboarding.airport.\(airport.iataCode ?? "")") {
                            model.choose(airport: airport)
                        }
                    }
                    }
                )
                .task(id: model.airportQuery) { await model.refreshAirports() }

                field(
                    label: L10n.text(K.search.form.nationality),
                    placeholder: L10n.text(K.search.nationality.placeholder),
                    chosen: model.passport?.nationality,
                    text: $model.nationalityQuery,
                    clear: { model.clearPassport() },
                    tid: "onboarding.passport",
                    rows: {
                    ForEach(model.nationalitySuggestions, id: \.self) { item in
                        suggestion(item.nationality ?? item.country ?? "", tid: "onboarding.passport.\(item.countryCode ?? "")") {
                            model.choose(nationality: item)
                        }
                    }
                    }
                )
                .task(id: model.nationalityQuery) { await model.refreshNationalities() }
            }
        }
    }

    static func airportLabel(_ airport: AirportSuggestion) -> String {
        let place = [airport.city, airport.country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let code = airport.iataCode ?? ""
        return [code, place.isEmpty ? (airport.name ?? "") : place].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func field<Rows: View>(
        label: String, placeholder: String, chosen: String?, text: Binding<String>,
        clear: @escaping () -> Void, tid: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: label)
                .font(VFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
            if let chosen {
                HStack(spacing: Spacing.sm) {
                    Text(verbatim: chosen)
                        .font(VFont.body(.body))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm)
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }
                    .foregroundStyle(SemanticColor.textMuted)
                    .accessibilityLabel(L10n.text(K.search.airport.clear))
                    .accessibilityIdentifier("\(tid).clear")
                }
                .padding(.leading, Spacing.md)
                .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(tid)
                VStack(alignment: .leading, spacing: Spacing.xs) { rows() }
            }
        }
    }

    private func suggestion(_ title: String, tid: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(VFont.body(.body))
                .foregroundStyle(SemanticColor.text)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier(tid)
    }
}
