import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The review the traveller edits before planning: route, places per stop, unplaced spots, trip basics.
struct ImportReview: View {
    @Bindable var model: ImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(verbatim: L10n.text(K.search.preview.found))
                .font(VFont.display(.title3))
                .foregroundStyle(SemanticColor.text)
            source
            route
            ForEach(model.includedStops) { stop in placesSection(stop) }
            if !model.unplaced.isEmpty { unplacedSection }
            trip
            planButton
        }
        .accessibilityIdentifier("import.review")
    }

    @ViewBuilder private var source: some View {
        if let result = model.result {
            let heading: String = {
                switch result.source?.kind {
                case "url": return result.source?.title ?? result.source?.siteName ?? L10n.text(K.search.preview.pageShared)
                case "images": return L10n.text(K.search.preview.yourShots)
                default: return L10n.text(K.search.preview.yourText)
                }
            }()
            VCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(verbatim: heading).font(VFont.body(.subheadline, weight: .semibold))
                        .foregroundStyle(SemanticColor.text)
                    if let summary = result.summary {
                        Text(verbatim: summary).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
        }
    }

    private var route: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.search.preview.route))
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                ForEach(model.stops) { stop in
                    HStack {
                        Toggle(isOn: Binding(get: { stop.included }, set: { model.setIncluded(stop.id, $0) })) {
                            Text(verbatim: stop.id).font(VFont.body(.subheadline))
                        }
                        .accessibilityIdentifier("import.stop.\(stop.id)")
                        Stepper(
                            value: Binding(get: { stop.nights }, set: { model.setNights(stop.id, $0) }), in: 1...30
                        ) {
                            Text(verbatim: L10n.text(K.search.preview.nights, count: stop.nights))
                                .font(VFont.body(.footnote))
                        }
                        .labelsHidden()
                        Text(verbatim: L10n.text(K.search.preview.nights, count: stop.nights))
                            .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
        }
    }

    private func placesSection(_ stop: ImportDraftStop) -> some View {
        let city = stop.id.split(separator: ",").first.map(String.init) ?? stop.id
        let rows = model.places.filter { $0.destination == stop.id }
        return VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.search.preview.placesIn, ["city": city]))
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                ForEach(rows) { row in PlaceRow(model: model, row: row) }
            }
        }
    }

    private var unplacedSection: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.search.preview.unplaced, count: model.unplaced.count))
                    .font(VFont.body(.subheadline, weight: .semibold))
                    .foregroundStyle(SemanticColor.text)
                Text(verbatim: L10n.text(K.search.preview.unplacedHint))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
                ForEach(model.unplaced) { row in UnplacedRow(model: model, row: row) }
            }
        }
    }

    private var trip: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField(L10n.text(K.search.form.cityOrAirport), text: $model.origin)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("import.origin")
                TextField(L10n.text(K.search.form.nationalityPlaceholder), text: $model.nationality)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("import.nationality")
                DatePicker(L10n.text(K.search.preview.leavingOn), selection: $model.departure, displayedComponents: .date)
                    .accessibilityIdentifier("import.departure")
                if let missing = model.missingField {
                    Text(verbatim: missing).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                }
            }
        }
    }

    private var planButton: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if model.plannedCount == 0 {
                Text(verbatim: L10n.text(K.search.preview.tickOne)).font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.textMuted)
            }
            VButton(
                L10n.text(K.search.preview.plan, count: model.plannedCount),
                tid: "import.plan", systemImage: "sparkles"
            ) { model.plan() }
            .disabled(!model.canPlan)
            VButton(L10n.text(K.search.preview.startOver), tid: "import.startOver", role: .secondary) { model.startOver() }
        }
    }
}

private struct PlaceRow: View {
    @Bindable var model: ImportModel
    let row: ImportDraftPlace
    @State private var renaming = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button { model.toggle(row.id) } label: {
                Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
            }
            .accessibilityLabel(L10n.text(K.search.preview.includeAria, ["name": row.name]))
            .accessibilityIdentifier("import.include.\(row.id)")
            if renaming {
                TextField(row.name, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.rename(row.id, to: draft)
                        renaming = false
                    }
                    .accessibilityLabel(L10n.text(K.search.preview.newNameAria, ["name": row.name]))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.name).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                    if row.place.approximate == true {
                        Text(verbatim: L10n.text(K.search.preview.approximate)).font(VFont.body(.caption))
                            .foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                draft = row.name
                renaming.toggle()
            } label: { Image(systemName: "pencil") }
            .accessibilityLabel(L10n.text(K.search.preview.renameAria, ["name": row.name]))
            Button(role: .destructive) { model.remove(row.id) } label: { Image(systemName: "trash") }
                .accessibilityLabel(L10n.text(K.search.preview.leaveOut))
        }
    }
}

private struct UnplacedRow: View {
    @Bindable var model: ImportModel
    let row: ImportDraftPlace
    @State private var town = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(verbatim: row.name).font(VFont.body(.subheadline, weight: .medium)).foregroundStyle(SemanticColor.text)
                Spacer(minLength: 0)
                Button(role: .destructive) { model.remove(row.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel(L10n.text(K.search.preview.leaveOut))
            }
            HStack {
                TextField(L10n.text(K.search.preview.whichTown), text: $town)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.text(K.search.preview.townFor, ["name": row.name]))
                    .accessibilityIdentifier("import.town.\(row.id)")
                Button(L10n.text(model.placing.contains(row.id) ? K.search.preview.placing : K.search.preview.placeIt)) {
                    Task { await model.place(row.id, town: town) }
                }
                .buttonStyle(.bordered)
                .disabled(town.trimmingCharacters(in: .whitespaces).isEmpty || model.placing.contains(row.id))
                .accessibilityIdentifier("import.placeIt.\(row.id)")
            }
            if !model.stops.isEmpty {
                Picker(L10n.text(K.search.preview.whichStop, ["name": row.name]), selection: Binding(
                    get: { row.destination ?? "" }, set: { model.assign(row.id, stop: $0.isEmpty ? nil : $0) })
                ) {
                    Text(verbatim: L10n.text(K.search.preview.leaveOut)).tag("")
                    ForEach(model.stops) { stop in Text(verbatim: stop.id).tag(stop.id) }
                }
                .font(VFont.body(.footnote))
            }
            if let problem = model.placeProblems[row.id] {
                Text(verbatim: problem).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
            }
        }
    }
}
