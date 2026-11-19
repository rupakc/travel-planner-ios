import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// The trip's carbon footprint, worked out by `POST /api/carbon/trip` (travel-planner `docs/Carbon-Footprint.md`):
/// total, per person, the breakdown bar, comparisons, the lower-carbon hint, the diet picker and "How we calculate"
/// (every line with its method, the assumptions and the sources). Numbers from the Voyager crawler arrive with
/// `crawler_sources` and a per-line `crawler_source`; an older or crawler-off backend sends neither and nothing extra
/// shows. The host decides `available` (`features.carbon`); the card also hides itself after a `404`.
public struct CarbonFootprintCard: View {
    public enum Mode: String, Sendable {
        /// The Results page: the search result summary.
        case results
        /// My Plan: the picked items (`compact`).
        case plan
    }

    private let mode: Mode
    private let available: Bool
    private let makeBody: @MainActor (String) -> JSONValue
    @State private var model: CarbonFootprintModel
    @State private var open = false

    /// `makeBody` builds the request for a diet (`CarbonRequest.fromResults` / `fromSelections`).
    public init(
        mode: Mode,
        available: Bool,
        makeBody: @escaping @MainActor (String) -> JSONValue,
        load: @escaping @MainActor @Sendable (JSONValue) async -> CarbonFetch
    ) {
        self.mode = mode
        self.available = available
        self.makeBody = makeBody
        _model = State(initialValue: CarbonFootprintModel(load: load))
    }

    public var body: some View {
        let request = makeBody(model.diet)
        if available {
            // Until the first answer the card shows "Working out the footprint…", so it is on screen and the task runs.
            CarbonCardContent(mode: mode, model: model, open: $open)
                .task(id: request) { model.request(request) }
        }
    }
}

/// The card over a model (no requests of its own).
struct CarbonCardContent: View {
    let mode: CarbonFootprintCard.Mode
    let model: CarbonFootprintModel
    @Binding var open: Bool
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        switch model.phase {
        case .gone:
            EmptyView()
        case .idle, .loading, .loaded, .failed:
            VCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    switch model.phase {
                    case .idle, .loading:
                        muted(L10n.text(K.results.carbon.loading))
                    case .failed:
                        muted(L10n.text(K.results.carbon.error))
                    default:
                        if let report = model.report { loaded(report) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("carbon.card.\(mode.rawValue)")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Label {
                Text(verbatim: L10n.text(K.results.carbon.title))
                    .font(VFont.display(.headline))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "leaf").foregroundStyle(Palette.color(.emerald, .s600))
            }
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            if model.phase == .loaded {
                Button {
                    Telemetry.shared.track(.uiTap(tid: "carbon.how", route: route))
                    open.toggle()
                } label: {
                    Label(L10n.text(K.results.carbon.how), systemImage: "info.circle")
                        .font(VFont.body(.caption, weight: .medium))
                        .foregroundStyle(SemanticColor.primary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(open ? .isSelected : [])
                .accessibilityIdentifier("carbon.how")
            }
        }
    }

    @ViewBuilder private func loaded(_ report: CarbonReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            totals(report)
            if report.totalKg > 0 {
                CarbonBar(categories: report.categories)
                legend(report)
                comparisons(report)
            }
            if !report.crawlerSources.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    muted(L10n.text(K.results.carbon.liveData))
                    ForEach(Array(report.crawlerSources.enumerated()), id: \.offset) { _, source in
                        CarbonSourceLine(source: source)
                    }
                }
                .accessibilityIdentifier("carbon.liveSources")
            }
            if let hint = report.railHint { railHint(hint) }
            dietPicker
            if open { CarbonHowPanel(report: report, onClose: { open = false }) }
        }
        .opacity(model.refreshing ? 0.7 : 1)
    }

    private func totals(_ report: CarbonReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: L10n.text(K.results.carbon.total, ["kg": CarbonText.kg0(report.totalKg)]))
                .font(VFont.display(mode == .plan ? .title3 : .title2))
                .foregroundStyle(SemanticColor.text)
                .monospacedDigit()
                .accessibilityIdentifier("carbon.total")
            if report.travellers > 1 {
                muted(L10n.text(K.results.carbon.perPerson, ["kg": CarbonText.kg0(report.perPersonKg)]))
            }
        }
    }

    private func legend(_ report: CarbonReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(report.categories) { category in
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(Palette.color(CarbonText.categoryFamily(category.key), .s500))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(verbatim: CarbonText.category(category.key))
                        .foregroundStyle(SemanticColor.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: L10n.text(K.results.carbon.kg, ["kg": CarbonText.kg0(category.kg)]))
                        .foregroundStyle(SemanticColor.text)
                        .monospacedDigit()
                    Text(verbatim: CarbonRequest.pctLabel(category.share))
                        .foregroundStyle(SemanticColor.textMuted)
                        .monospacedDigit()
                        .frame(minWidth: 36, alignment: .trailing)
                }
                .font(VFont.body(.caption))
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func comparisons(_ report: CarbonReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if report.carKm > 0 {
                muted(L10n.text(K.results.carbon.carKm, ["km": Fmt.number(report.carKm)]))
            }
            if report.budgetShare > 0 {
                muted(L10n.text(
                    K.results.carbon.budget,
                    ["pct": CarbonRequest.pctLabel(report.budgetShare), "tonnes": Fmt.number(report.annualBudgetKg / 1000)]))
            }
        }
    }

    private func railHint(_ hint: CarbonReport.RailHint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Image(systemName: "tram.fill").accessibilityHidden(true)
            Text(verbatim: L10n.text(
                K.results.carbon.railHint,
                ["route": hint.route, "km": Fmt.number(hint.railKm), "kg": CarbonText.kg0(hint.savingKg)]))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(VFont.body(.caption))
        .foregroundStyle(Palette.color(.emerald, .s800))
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .borderedSurface(
            RoundedRectangle(cornerRadius: Radius.input), fill: Palette.color(.emerald, .s50),
            border: Palette.color(.emerald, .s200))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("carbon.railHint")
    }

    private var dietPicker: some View {
        HStack(spacing: Spacing.sm) {
            muted(L10n.text(K.results.carbon.diet.label))
            Picker(
                L10n.text(K.results.carbon.diet.label),
                selection: Binding(
                    get: { model.diet },
                    set: { value in
                        Telemetry.shared.track(.uiTap(tid: "carbon.diet", route: route))
                        model.setDiet(value)
                    })
            ) {
                ForEach(CarbonRequest.diets, id: \.self) { diet in
                    Text(verbatim: CarbonText.diet(diet)).tag(diet)
                }
            }
            .pickerStyle(.menu)
            .tint(SemanticColor.primary)
            .accessibilityIdentifier("carbon.diet")
        }
    }

    private func muted(_ text: String) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.caption))
            .foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The breakdown bar: one coloured segment per category, as wide as its share.
struct CarbonBar: View {
    let categories: [CarbonReport.Category]

    var body: some View {
        GeometryReader { geometry in
            let gaps = CGFloat(max(0, categories.count - 1))
            let width = max(0, geometry.size.width - gaps)
            HStack(spacing: 1) {
                ForEach(categories) { category in
                    Rectangle()
                        .fill(Palette.color(CarbonText.categoryFamily(category.key), .s500))
                        .frame(width: width * CGFloat(min(1, max(0, category.share))))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(Palette.color(.gray, .s100))
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(categories
            .map { "\(CarbonText.category($0.key)) \(CarbonRequest.pctLabel($0.share))" }
            .joined(separator: ", "))
        .accessibilityIdentifier("carbon.bar")
    }
}

/// "How we calculate": the intro, every line (method, label, kg, and the crawler source when one was used), the
/// assumptions and the sources with their licences and attributions.
struct CarbonHowPanel: View {
    let report: CarbonReport
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                text(L10n.text(K.results.carbon.howIntro), muted: false)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(SemanticColor.textMuted)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text(K.results.carbon.close))
                .accessibilityIdentifier("carbon.how-close")
            }
            group(L10n.text(K.results.carbon.linesTitle)) {
                ForEach(Array(report.lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            MethodTag(method: line.method)
                            text(CarbonText.line(line), muted: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: L10n.text(K.results.carbon.kg, ["kg": CarbonText.kg1(line.kg)]))
                                .font(VFont.body(.caption, weight: .medium))
                                .foregroundStyle(SemanticColor.text)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        if let source = line.crawlerSource { CarbonSourceLine(source: source) }
                    }
                }
            }
            if !report.assumptions.isEmpty {
                group(L10n.text(K.results.carbon.assumptionsTitle)) {
                    ForEach(Array(report.assumptions.enumerated()), id: \.offset) { _, assumption in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                            Text(verbatim: "•").accessibilityHidden(true)
                            text(CarbonText.assumption(assumption), muted: false)
                        }
                        .font(VFont.body(.caption))
                    }
                }
            }
            group(L10n.text(K.results.carbon.sourcesTitle)) {
                ForEach(Array(report.sources.enumerated()), id: \.offset) { _, source in
                    SourceRow(source: source)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .borderedSurface(
            RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surface, border: SemanticColor.border)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("carbon.howPanel")
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: title)
                .font(VFont.body(.caption, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func text(_ value: String, muted: Bool) -> some View {
        Text(verbatim: value)
            .font(VFont.body(.caption))
            .foregroundStyle(muted ? SemanticColor.textMuted : SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MethodTag: View {
    let method: String

    var body: some View {
        let family = CarbonText.methodFamily(method)
        Text(verbatim: CarbonText.method(method))
            .font(VFont.body(.caption2, weight: .medium))
            .foregroundStyle(Palette.color(family, .s700))
            .padding(.horizontal, Spacing.xs)
            .borderedSurface(
                RoundedRectangle(cornerRadius: 4), fill: Palette.color(family, .s50), border: Palette.color(family, .s200))
            .fixedSize()
    }
}

private struct SourceRow: View {
    let source: CarbonReport.Source

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let url = source.url {
                Link(destination: url) {
                    Text(verbatim: source.name).underline()
                }
                .tint(SemanticColor.primary)
            } else {
                Text(verbatim: source.name).foregroundStyle(SemanticColor.text)
            }
            let extra = [source.publisher, source.licence].compactMap { $0 }.joined(separator: " · ")
            if !extra.isEmpty {
                Text(verbatim: extra).foregroundStyle(SemanticColor.textMuted)
            }
            if let attribution = source.attribution {
                Text(verbatim: attribution).foregroundStyle(SemanticColor.textMuted)
            }
        }
        .font(VFont.body(.caption))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Source: <name> · as of <date>" with the licence attribution under it (the web's `SourceLine`).
struct CarbonSourceLine: View {
    let source: CarbonReport.Source

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                let title = L10n.text(K.results.official.source, ["name": source.name])
                if let url = source.url {
                    Link(destination: url) { Text(verbatim: title) }
                        .tint(SemanticColor.primary)
                } else {
                    Text(verbatim: title)
                }
                if let day = CarbonText.day(source.asOf) {
                    Text(verbatim: "· " + L10n.text(K.results.official.asOf, ["date": day]))
                }
            }
            if let attribution = source.attribution {
                if let url = source.licenceURL {
                    Link(destination: url) { Text(verbatim: attribution) }
                        .tint(SemanticColor.textMuted)
                } else {
                    Text(verbatim: attribution)
                }
            }
        }
        .font(VFont.body(.caption2))
        .foregroundStyle(SemanticColor.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("carbon.source")
    }
}
