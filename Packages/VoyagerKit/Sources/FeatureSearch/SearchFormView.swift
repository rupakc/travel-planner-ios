import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// The Search form, known-destination mode (web `SearchPage` "known"): route, stops, dates, nationality, budget,
/// travellers, permits and visas, interests, pace and the discovery dial. AppShell hosts it in the Explore tab.
public struct SearchFormView: View {
    let env: AppEnvironment
    @State private var model: SearchFormModel

    @MainActor public init(env: AppEnvironment, prefill: TravelSearchRequest?) {
        self.env = env
        _model = State(initialValue: SearchFormModel(env: env, prefill: prefill))
    }

    /// For snapshots and previews: a prepared model.
    @MainActor init(env: AppEnvironment, model: SearchFormModel) {
        self.env = env
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let notice = model.notice { noticeBanner(notice) }
                RecentSearchesList(model: model)
                routeSection
                MultiCityEditor(model: model)
                datesSection
                NationalityField(model: model)
                budgetField
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    label(K.search.form.travelers)
                    TravelerPanel(model: model)
                }
                TagInput(
                    label: L10n.text(K.search.form.permits), placeholder: L10n.text(K.search.form.permitsPlaceholder),
                    tid: "search.permits", tags: $model.permits)
                TagInput(
                    label: L10n.text(K.search.form.visas), placeholder: L10n.text(K.search.form.visasPlaceholder),
                    tid: "search.visas", tags: $model.visas)
                InterestPicker(model: model)
                paceSection
                dialSection
                if let issue = model.visibleIssue { issueText(issue) }
                VButton(L10n.text(K.search.form.plan), tid: "search.plan", systemImage: "magnifyingglass") {
                    model.submit()
                }
                .disabled(model.issue == .returnBeforeDeparture)
            }
            .padding(Spacing.lg)
            .readableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SemanticColor.surface)
        .task { await model.load() }
    }

    // MARK: - Sections

    private var routeSection: some View {
        AdaptiveColumns {
            VStack(alignment: .leading, spacing: Spacing.md) { routeFields }
        } regular: {
            HStack(alignment: .top, spacing: Spacing.lg) { routeFields }
        }
    }

    @ViewBuilder private var routeFields: some View {
        AirportField(model: model, field: model.origin, label: L10n.text(K.search.form.from), tid: "search.origin")
        AirportField(model: model, field: model.destination, label: L10n.text(K.search.form.to), tid: "search.destination")
    }

    private var datesSection: some View {
        AdaptiveColumns {
            VStack(alignment: .leading, spacing: Spacing.md) { dateFields }
        } regular: {
            HStack(alignment: .top, spacing: Spacing.lg) { dateFields }
        }
    }

    @ViewBuilder private var dateFields: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            label(K.search.form.departure)
            DatePicker(
                L10n.text(K.search.form.departure), selection: $model.departure, in: model.today..., displayedComponents: .date
            )
            .labelsHidden()
            .environment(\.locale, env.language.language.intlLocale)
            .accessibilityIdentifier("search.departure")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: $model.hasReturn) {
                label(K.search.form.return)
            }
            .accessibilityIdentifier("search.hasReturn")
            if model.hasReturn {
                DatePicker(
                    L10n.text(K.search.form.return), selection: $model.returnDate, in: model.departure..., displayedComponents: .date
                )
                .labelsHidden()
                .environment(\.locale, env.language.language.intlLocale)
                .accessibilityIdentifier("search.return")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var budgetField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            label(K.search.form.budget)
            TextField(L10n.text(K.search.form.optional), text: $model.budgetText)
                .keyboardType(.decimalPad)
                .font(VFont.body(.body))
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(SemanticColor.border, lineWidth: 1) }
                .accessibilityIdentifier("search.budget")
        }
    }

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            label(K.search.pace.label)
            FlowLayout(spacing: Spacing.sm) {
                ForEach(SearchFormModel.paceIDs, id: \.self) { id in
                    VChip(title: Self.paceLabel(id), tid: "search.pace.\(id)", selected: model.pace == id) {
                        model.pace = model.pace == id ? nil : id
                    }
                }
            }
        }
    }

    private var dialSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                label(K.search.dial.label)
                Spacer(minLength: Spacing.sm)
                Text(verbatim: dialName)
                    .font(VFont.body(.footnote, weight: .semibold))
                    .foregroundStyle(SemanticColor.primary)
            }
            Slider(value: $model.serendipity, in: 0...1, step: 0.05)
                .tint(SemanticColor.primary)
                .accessibilityLabel(L10n.text(K.search.dial.aria))
                .accessibilityIdentifier("search.dial")
            HStack {
                Text(verbatim: L10n.text(K.search.dial.iconic))
                Spacer(minLength: Spacing.sm)
                Text(verbatim: L10n.text(K.search.dial.offBeaten))
            }
            .font(VFont.body(.caption))
            .foregroundStyle(SemanticColor.textMuted)
        }
    }

    private var dialName: String {
        if model.serendipity < 0.33 { return L10n.text(K.search.dial.classics) }
        return model.serendipity > 0.66 ? L10n.text(K.search.dial.gems) : L10n.text(K.search.dial.balanced)
    }

    // MARK: - Pieces

    private func label(_ key: LKey) -> some View {
        Text(verbatim: L10n.text(key))
            .font(VFont.body(.subheadline, weight: .semibold))
            .foregroundStyle(SemanticColor.text)
    }

    private func issueText(_ issue: SearchFormIssue) -> some View {
        let key = issue == .returnBeforeDeparture ? K.search.validation.returnBeforeDeparture : K.search.validation.required
        return Text(verbatim: L10n.text(key))
            .font(VFont.body(.footnote, weight: .medium))
            .foregroundStyle(SemanticColor.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("search.issue")
    }

    private func noticeBanner(_ notice: RecentNotice) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(verbatim: L10n.text(
                notice.datesShifted ? K.search.recent.loadedShifted : K.search.recent.loaded, ["route": notice.route]))
                .font(VFont.body(.footnote))
                .foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.sm)
            Button { model.dismissNotice() } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .foregroundStyle(SemanticColor.textMuted)
            .accessibilityLabel(L10n.text(K.search.recent.dismiss))
            .accessibilityIdentifier("search.notice.dismiss")
        }
        .padding(.leading, Spacing.md)
        .background(SemanticColor.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(SemanticColor.border, lineWidth: 1) }
    }

    static func paceLabel(_ id: String) -> String {
        switch id {
        case "relaxed": L10n.text(K.onboarding.quiz.pace.options.relaxed)
        case "balanced": L10n.text(K.onboarding.quiz.pace.options.balanced)
        default: L10n.text(K.onboarding.quiz.pace.options.packed)
        }
    }
}
