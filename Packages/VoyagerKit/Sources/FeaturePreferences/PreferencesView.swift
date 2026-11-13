import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// Travel preferences: Taste Graph, budget, identity and email, documents, travel group and interests.
public struct PreferencesView: View {
    @State private var model: PreferencesModel
    @State private var taste: TasteModel
    @State private var email: EmailModel

    @MainActor public init(env: AppEnvironment) {
        _model = State(initialValue: PreferencesModel(env: env))
        _taste = State(initialValue: TasteModel(env: env))
        _email = State(initialValue: EmailModel(env: env))
    }

    @MainActor init(model: PreferencesModel, taste: TasteModel, email: EmailModel) {
        _model = State(initialValue: model)
        _taste = State(initialValue: taste)
        _email = State(initialValue: email)
    }

    public var body: some View {
        ScrollView {
            // VStack, not LazyVStack: lazy stacks hang hosted snapshot tests.
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text(verbatim: L10n.text(K.account.prefs.subtitle))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                VCard { TasteProfileCard(model: taste) }
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(Spacing.xl)
                        .accessibilityIdentifier("prefs.loading")
                case .failed:
                    VStack(spacing: Spacing.sm) {
                        ErrorState(error: model.loadError) { Task { await model.load() } }
                        Text(verbatim: L10n.text(K.account.prefs.loadFailed))
                            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                    }
                case .loaded:
                    form
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .navigationTitle(L10n.text(K.account.prefs.title))
        .task {
            // A model that is already loaded (tests, a rebuilt view) is not reloaded.
            async let prefs: Void = model.phase == .loading ? model.load() : ()
            async let learned: Void = taste.phase == .loading ? taste.load() : ()
            _ = await (prefs, learned)
        }
        .telemetryScreen(TelemetryRouteName.template(for: .preferences))
        .accessibilityIdentifier("prefs.root")
    }

    @ViewBuilder private var form: some View {
        budget
        identity
        documents
        style
        saveBar
    }

    private var budget: some View {
        PrefsGroup(title: L10n.text(K.account.prefs.budget.section)) {
            Text(verbatim: L10n.text(K.account.prefs.budget.category))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            ForEach(PreferencesModel.budgets, id: \.self) { value in
                budgetRow(value)
            }
        }
    }

    private func budgetRow(_ value: String) -> some View {
        let (label, desc) = Self.budgetCopy(value)
        let selected = model.budget == value
        return Button { model.budget = value } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? SemanticColor.primary : SemanticColor.textMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                    Text(verbatim: desc).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("prefs.budget.\(value)")
    }

    private static func budgetCopy(_ value: String) -> (String, String) {
        switch value {
        case "low": (L10n.text(K.account.prefs.budget.low.label), L10n.text(K.account.prefs.budget.low.desc))
        case "high": (L10n.text(K.account.prefs.budget.high.label), L10n.text(K.account.prefs.budget.high.desc))
        default: (L10n.text(K.account.prefs.budget.medium.label), L10n.text(K.account.prefs.budget.medium.desc))
        }
    }

    private var identity: some View {
        PrefsGroup(title: L10n.text(K.account.prefs.identity.section)) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.account.prefs.identity.nationality))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                TextField(L10n.text(K.account.prefs.identity.nationalityPlaceholder), text: $model.nationality)
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .accessibilityIdentifier("prefs.nationality")
                    .task(id: model.nationality) {
                        try? await Task.sleep(for: .milliseconds(250))
                        if !Task.isCancelled { await model.searchNationalities(model.nationality) }
                    }
                ForEach(Array(model.nationalitySuggestions.enumerated()), id: \.offset) { _, suggestion in
                    Button { model.pickNationality(suggestion) } label: {
                        Text(verbatim: [suggestion.nationality, suggestion.country].compactMap { $0 }.joined(separator: " · "))
                            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("prefs.nationality.suggestion")
                }
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.account.prefs.identity.residence))
                    .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                TextField(L10n.text(K.account.prefs.identity.residencePlaceholder), text: $model.residence)
                    .textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .accessibilityIdentifier("prefs.residence")
                Text(verbatim: L10n.text(K.account.prefs.identity.residenceHint))
                    .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
            EmailField(model: email)
        }
    }

    private var documents: some View {
        PrefsGroup(title: L10n.text(K.account.prefs.documents.section)) {
            TagField(
                label: L10n.text(K.account.prefs.documents.permits),
                placeholder: L10n.text(K.account.prefs.documents.permitsPlaceholder), tid: "prefs.permits",
                tags: model.permits, add: { model.addTag($0, to: \.permits) }, remove: { model.removeTag($0, from: \.permits) })
            TagField(
                label: L10n.text(K.account.prefs.documents.visas),
                placeholder: L10n.text(K.account.prefs.documents.visasPlaceholder), tid: "prefs.visas",
                tags: model.visas, add: { model.addTag($0, to: \.visas) }, remove: { model.removeTag($0, from: \.visas) })
        }
    }

    private var style: some View {
        PrefsGroup(title: L10n.text(K.account.prefs.style.section)) {
            Text(verbatim: L10n.text(K.account.prefs.style.group))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            ForEach(TravelerGroup.allCases, id: \.self) { group in
                stepper(group)
            }
            Text(verbatim: L10n.text(K.search.travelers.accessibility))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            ForEach(PreferencesModel.accessIDs, id: \.self) { id in
                Toggle(isOn: Binding(get: { model.access.contains(id) }, set: { _ in model.toggleAccess(id) })) {
                    Text(verbatim: Self.accessTitle(id)).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("prefs.access.\(id)")
            }
            Text(verbatim: L10n.text(K.account.prefs.style.groupHint))
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            Text(verbatim: L10n.text(K.account.prefs.style.interests))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            ChipGrid(items: PreferencesModel.interestIDs) { id in
                VChip(title: Self.interestTitle(id), tid: "prefs.interest.\(id)", selected: model.interests.contains(id)) {
                    model.toggleInterest(id)
                }
            }
        }
    }

    private func stepper(_ group: TravelerGroup) -> some View {
        let title = Self.groupTitle(group)
        return Stepper(
            value: Binding(get: { model.count(group) }, set: { model.setCount(group, $0) }),
            in: 0...PreferencesModel.maxPerGroup
        ) {
            Text(verbatim: "\(title): \(model.count(group))")
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("prefs.count.\(group.rawValue)")
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VButton(
                model.saving ? L10n.text(K.account.prefs.saving) : L10n.text(K.account.prefs.save), tid: "prefs.save",
                systemImage: "checkmark"
            ) { Task { await model.save() } }
            .disabled(model.saving)
            if let message = model.saveMessage {
                Text(verbatim: message)
                    .font(VFont.body(.subheadline))
                    .foregroundStyle(model.saveFailed ? SemanticColor.destructive : SemanticColor.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("prefs.saveMessage")
            }
        }
    }

    private static func groupTitle(_ group: TravelerGroup) -> String {
        switch group {
        case .adults: L10n.text(K.search.travelers.adults)
        case .seniors: L10n.text(K.search.travelers.seniors)
        case .children: L10n.text(K.search.travelers.children)
        case .infants: L10n.text(K.search.travelers.infants)
        }
    }

    private static func accessTitle(_ id: String) -> String {
        switch id {
        case "wheelchair": L10n.text(K.search.travelers.access.wheelchair)
        case "visual_impairment": L10n.text(K.search.travelers.access.visual_impairment)
        case "hearing_impairment": L10n.text(K.search.travelers.access.hearing_impairment)
        default: L10n.text(K.search.travelers.access.cognitive_disability)
        }
    }

    private static func interestTitle(_ id: String) -> String {
        switch id {
        case "food": L10n.text(K.account.prefs.interest.food)
        case "history": L10n.text(K.account.prefs.interest.history)
        case "adventure": L10n.text(K.account.prefs.interest.adventure)
        case "culture": L10n.text(K.account.prefs.interest.culture)
        case "nature": L10n.text(K.account.prefs.interest.nature)
        case "shopping": L10n.text(K.account.prefs.interest.shopping)
        case "nightlife": L10n.text(K.account.prefs.interest.nightlife)
        case "wellness": L10n.text(K.account.prefs.interest.wellness)
        case "art": L10n.text(K.account.prefs.interest.art)
        default: L10n.text(K.account.prefs.interest.family)
        }
    }
}
