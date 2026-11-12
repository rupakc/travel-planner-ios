import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// Up to three stops on the way to the destination, each with an optional number of nights.
struct MultiCityEditor: View {
    let model: SearchFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ForEach(Array(model.stops.enumerated()), id: \.element.id) { index, stop in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    AirportField(
                        model: model, field: stop.place,
                        label: L10n.text(K.search.stops.label, ["n": "\(index + 1)"]), tid: "search.stop.\(index)")
                    HStack(spacing: Spacing.sm) {
                        Text(verbatim: "\(L10n.text(K.search.stops.nights)) \(L10n.text(K.search.stops.optional))")
                            .font(VFont.body(.footnote))
                            .foregroundStyle(SemanticColor.textMuted)
                        TextField(
                            L10n.text(K.search.stops.auto),
                            text: Binding(get: { stop.nights }, set: { model.setNights($0, forStop: stop.id) })
                        )
                        .keyboardType(.numberPad)
                        .font(VFont.body(.body))
                        .multilineTextAlignment(.center)
                        .frame(width: 72, height: 44)
                        .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(SemanticColor.border, lineWidth: 1) }
                        .accessibilityIdentifier("search.stop.\(index).nights")
                        Spacer(minLength: 0)
                        Button { model.removeStop(id: stop.id) } label: {
                            Image(systemName: "xmark.circle").frame(width: 44, height: 44)
                        }
                        .foregroundStyle(SemanticColor.textMuted)
                        .accessibilityLabel(L10n.text(K.search.stops.remove))
                        .accessibilityIdentifier("search.stop.\(index).remove")
                    }
                }
            }
            if model.canAddStop {
                VButton(L10n.text(K.search.stops.add), tid: "search.stop.add", role: .tonal, systemImage: "plus") {
                    model.addStop()
                }
            }
            if !model.stops.isEmpty { routeNote }
        }
    }

    private var routeNote: some View {
        let names = model.filledStops.map { SearchFormModel.short($0.city) }.joined(separator: " → ")
        let args = [
            "origin": model.origin.value.isEmpty ? L10n.text(K.search.stops.originFallback) : SearchFormModel.short(model.origin.value),
            "stops": names.isEmpty ? L10n.text(K.search.stops.stopsFallback) : names,
            "destination": model.destination.value.isEmpty
                ? L10n.text(K.search.stops.destinationFallback) : SearchFormModel.short(model.destination.value),
        ]
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L10n.attributed(K.search.stops.route, args))
            Text(verbatim: L10n.text(K.search.stops.routeNote))
        }
        .font(VFont.body(.footnote))
        .foregroundStyle(SemanticColor.textMuted)
    }
}
